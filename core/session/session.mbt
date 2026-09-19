// Session：把多个 tool call 的参数片段路由到互相独立的解析器。
//
// 一次响应里可能同时出现多个 tool call，参数片段还会交错到达。Session 用
// 复合键（response / choice / index）分流，保证两条流不会被拼成同一个对象。

///|
/// 一个 tool call 的稳定复合键。
///
/// 只用 `index` 不够：同一响应里不同 choice 可以各有 index 0，不同响应也会重号。
pub(all) struct CallKey {
  /// 响应或流的标识；调用方没有提供时用空字符串。
  response : String
  /// choice 序号。
  choice : Int
  /// 该 choice 内的 tool call 序号。
  index : Int
} derive(Eq, Debug, ToJson)

///|
pub fn CallKey::new(response? : String, choice? : Int, index? : Int) -> CallKey {
  {
    response: match response {
      Some(value) => value
      None => ""
    },
    choice: match choice {
      Some(value) => value
      None => 0
    },
    index: match index {
      Some(value) => value
      None => 0
    },
  }
}

///|
/// 路由层面的错误。适配层应当把它们当作"输入流组织方式不对"来报告，
/// 而不是当作模型输出不合法。
pub(all) suberror SessionError {
  /// 该调用还没有起始上下文（没有先 `open`）。
  UnknownCall(key~ : CallKey)
  /// 同一调用被赋予了不同的 id。
  CallIdConflict(key~ : CallKey, existing~ : String, incoming~ : String)
  /// 同一调用被赋予了不同的函数名。
  CallNameConflict(key~ : CallKey, existing~ : String, incoming~ : String)
  /// 会话的限制参数非法。包装主库的 `InvalidLimits`，使本包只有一个错误通道。
  InvalidLimits(error~ : @moonstream.ParseError)
  /// 该调用自身的解析失败。
  ParseFailed(key~ : CallKey, error~ : @moonstream.ParseError)
} derive(Eq, Debug, ToJson)

///|
/// 一个已打开的调用。
priv struct CallEntry {
  key : CallKey
  parser : @moonstream.Parser
  mut id : String?
  mut name : String?
  mut state : CallState
}

///|
priv enum CallState {
  Open
  Failed(@moonstream.ParseError)
  Finished
}

///|
/// 多 tool call 会话。
pub struct Session {
  inner : SessionState
}

///|
/// 会话的全部状态。私有实现细节，不是可用 API。
struct SessionState {
  limits : @moonstream.Limits
  calls : Array[CallEntry]
}

///|
/// 创建会话。限制在创建时校验，之后传给每个调用的解析器。
///
/// **限制是每个调用各自计数的**：`max_total_bytes` 约束的是单个调用的参数字节数，
/// 不是整个会话的累计量。会话里能开多少调用由调用方自己控制。
///
/// 限制非法时抛 `SessionError::InvalidLimits`（本包只有一个错误通道）。
pub fn Session::new(limits? : @moonstream.Limits) -> Session raise SessionError {
  let limits = match limits {
    Some(value) => value
    None => @moonstream.Limits::strict()
  }
  // 用一次构造校验限制；解析器各自也会再校验。
  try @moonstream.Parser::new(limits~) catch {
    err => raise SessionError::InvalidLimits(error=err)
  } noraise {
    _ => ()
  }
  { inner: { limits, calls: [] } }
}

///|
/// 注册一个调用的起始上下文。
///
/// `id` 与 `name` 是带默认值的标签参数，类型都是 `String?`，因此适配层可以直接透传
/// SDK 的 Option 字段：`open(key, id=delta.id, name=delta.name)`。
/// 重复注册同一个键是允许的（id / name 可以只在第一帧出现），
/// 但 id 或函数名冲突会报错，避免把两个不同调用混在一起。
pub fn Session::open(
  self : Session,
  key : CallKey,
  id? : String? = None,
  name? : String? = None,
) -> Unit raise SessionError {
  let entry = match self.find(key) {
    Some(entry) => entry
    None => {
      let parser = @moonstream.Parser::new(limits=self.inner.limits) catch {
        err => raise SessionError::ParseFailed(key~, error=err)
      }
      let entry = { key, parser, id: None, name: None, state: Open }
      self.inner.calls.push(entry)
      entry
    }
  }
  // 先完成全部冲突校验，再写入元数据，避免 name 冲突留下半更新状态。
  match id {
    Some(incoming) =>
      match entry.id {
        Some(existing) =>
          if existing != incoming {
            raise SessionError::CallIdConflict(key~, existing~, incoming~)
          }
        None => ()
      }
    None => ()
  }
  match name {
    Some(incoming) =>
      match entry.name {
        Some(existing) =>
          if existing != incoming {
            raise SessionError::CallNameConflict(key~, existing~, incoming~)
          }
        None => ()
      }
    None => ()
  }
  if entry.id is None {
    entry.id = id
  }
  if entry.name is None {
    entry.name = name
  }
}

///|
/// 把一段参数片段交给该调用自己的解析器。
pub fn Session::feed(
  self : Session,
  key : CallKey,
  bytes : Bytes,
) -> Array[@moonstream.Event] raise SessionError {
  let entry = match self.find(key) {
    Some(entry) => entry
    None => raise SessionError::UnknownCall(key~)
  }
  match entry.state {
    Failed(error) => raise SessionError::ParseFailed(key~, error~)
    Finished =>
      raise SessionError::ParseFailed(
        key~,
        error=@moonstream.ParseError::AlreadyFinished(op="feed"),
      )
    Open => ()
  }
  try entry.parser.feed(bytes) catch {
    err => {
      entry.state = Failed(err)
      raise SessionError::ParseFailed(key~, error=err)
    }
  } noraise {
    events => events
  }
}

///|
/// 把一段 UTF-8 文本增量交给该调用自己的解析器。
///
/// 适合直接接收 LLM SDK 的 `String` 参数片段；偏移仍按 UTF-8 字节计数。
pub fn Session::feed_text(
  self : Session,
  key : CallKey,
  text : StringView,
) -> Array[@moonstream.Event] raise SessionError {
  let entry = match self.find(key) {
    Some(entry) => entry
    None => raise SessionError::UnknownCall(key~)
  }
  match entry.state {
    Failed(error) => raise SessionError::ParseFailed(key~, error~)
    Finished =>
      raise SessionError::ParseFailed(
        key~,
        error=@moonstream.ParseError::AlreadyFinished(op="feed_text"),
      )
    Open => ()
  }
  try entry.parser.feed_text(text) catch {
    err => {
      entry.state = Failed(err)
      raise SessionError::ParseFailed(key~, error=err)
    }
  } noraise {
    events => events
  }
}

///|
/// 结束该调用，返回它的收尾事件与结果。其它调用不受影响。
pub fn Session::finish(
  self : Session,
  key : CallKey,
  reason? : @moonstream.EndReason,
) -> (Array[@moonstream.Event], @moonstream.FinishResult) raise SessionError {
  let entry = match self.find(key) {
    Some(entry) => entry
    None => raise SessionError::UnknownCall(key~)
  }
  match entry.state {
    Failed(error) => raise SessionError::ParseFailed(key~, error~)
    Finished =>
      raise SessionError::ParseFailed(
        key~,
        error=@moonstream.ParseError::AlreadyFinished(op="finish"),
      )
    Open => ()
  }
  try entry.parser.finish(reason?) catch {
    err => {
      entry.state = Failed(err)
      raise SessionError::ParseFailed(key~, error=err)
    }
  } noraise {
    outcome => {
      entry.state = Finished
      outcome
    }
  }
}

///|
/// 该调用是否仍可继续接收输入。
pub fn Session::is_open(self : Session, key : CallKey) -> Bool {
  match self.find(key) {
    Some(entry) => entry.state is Open
    None => false
  }
}

///|
/// 该调用是否已经 `finish`。
pub fn Session::is_finished(self : Session, key : CallKey) -> Bool {
  match self.find(key) {
    Some(entry) => entry.state is Finished
    None => false
  }
}

///|
/// 该调用是否因解析错误进入不可恢复状态。
pub fn Session::is_failed(self : Session, key : CallKey) -> Bool {
  match self.find(key) {
    Some(entry) => entry.state is Failed(_)
    None => false
  }
}

///|
/// 返回使该调用终止的原始解析错误。
pub fn Session::failure(
  self : Session,
  key : CallKey,
) -> @moonstream.ParseError? {
  match self.find(key) {
    Some({ state: Failed(error), .. }) => Some(error)
    _ => None
  }
}

///|
/// 已注册调用的数量（含已结束的）。
pub fn Session::call_count(self : Session) -> Int {
  self.inner.calls.length()
}

///|
/// 全部已注册的调用键（含已结束的），按注册顺序。
pub fn Session::calls(self : Session) -> Array[CallKey] {
  let out = []
  for entry in self.inner.calls {
    out.push(entry.key)
  }
  out
}

///|
/// 仍可继续接收输入的调用键，按注册顺序；失败与已结束调用不包含在内。
pub fn Session::open_calls(self : Session) -> Array[CallKey] {
  let out = []
  for entry in self.inner.calls {
    if entry.state is Open {
      out.push(entry.key)
    }
  }
  out
}

///|
/// 该调用已经消费的字节数。
pub fn Session::offset(self : Session, key : CallKey) -> Int? {
  match self.find(key) {
    Some(entry) => Some(entry.parser.offset())
    None => None
  }
}

///|
/// 该调用已知的 id。
pub fn Session::call_id(self : Session, key : CallKey) -> String? {
  match self.find(key) {
    Some(entry) => entry.id
    None => None
  }
}

///|
/// 该调用已知的函数名。
pub fn Session::call_name(self : Session, key : CallKey) -> String? {
  match self.find(key) {
    Some(entry) => entry.name
    None => None
  }
}

///|
/// 按复合键查找调用。
fn Session::find(self : Session, key : CallKey) -> CallEntry? {
  for entry in self.inner.calls {
    if entry.key == key {
      return Some(entry)
    }
  }
  None
}
