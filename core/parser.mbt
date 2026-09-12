///|
/// 容器帧的类型。
priv enum FrameKind {
  Obj
  Arr
}

///|
/// 当前语法上下文：下一个非空白字节应该是什么。
priv enum Ctx {
  /// 文档尚未开始，期待根值。
  RootStart
  /// 根值已完成，只允许空白。
  RootDone
  /// 对象内：期待键或 `}`。
  ObjKeyOrEnd
  /// 对象内 `,` 之后：只允许键。
  ObjKey
  /// 键之后：期待 `:`。
  ObjColon
  /// `:` 之后：期待值。
  ObjValue
  /// 成员值之后：期待 `,` 或 `}`。
  ObjCommaOrEnd
  /// 数组内：期待值或 `]`。
  ArrValueOrEnd
  /// 数组内 `,` 之后：期待值。
  ArrValue
  /// 元素值之后：期待 `,` 或 `]`。
  ArrCommaOrEnd
}

///|
/// 词法子状态。
priv enum LexKind {
  /// 结构化扫描（空白与结构字符）。
  LexNormal
  /// 字符串内部。
  LexStr
  /// 反斜杠之后。
  LexStrEscape
  /// `\uXXXX` 已读 n 位。
  LexStrHex(Int, Int)
  /// 已读到高位代理，等待 `\`。
  LexStrLowSlash(Int)
  /// 已读到高位代理，等待 `u`。
  LexStrLowU(Int)
  /// 低位代理的 4 位十六进制，已读 n 位。
  LexStrLowHex(Int, Int, Int)
  /// 数字内部。
  LexNum
  /// true / false / null 逐字匹配，已匹配 matched 个字符。
  LexLit(LitKind, Int)
}

///|
/// 字面量种类。
priv enum LitKind {
  LitTrue
  LitFalse
  LitNull
}

///|
/// 数字词法子状态。
priv enum NumState {
  /// 刚读到 `-`。
  NumSign
  /// 整数部分为 `0`。
  NumZero
  /// 整数部分已有非零起始数字。
  NumInt
  /// 刚读到 `.`。
  NumDot
  /// 小数部分至少一位。
  NumFrac
  /// 刚读到 `e` / `E`。
  NumExp
  /// 刚读到指数符号。
  NumExpSign
  /// 指数至少一位数字。
  NumExpDigits
}

///|
/// 一个已打开的容器。
priv struct Frame {
  kind : FrameKind
  /// 已完成的成员（对象）或元素（数组）数量。
  mut count : Int
  /// 已出现的键，用于重复键检测。
  keys : Map[String, Unit]
  /// 该容器的路径。
  path : Path
  /// 该键对应的值路径。键完成时算一次，值事件直接复用，避免重复分配。
  mut pending_path : Path
}

///|
/// 增量 JSON 解析器。
///
/// 它消费**已经提取出来的参数片段字节**，不负责连接模型或解析 SSE。
/// 同一个解析器实例只处理一个 JSON 文档。
///
/// 内部状态收在一个私有类型的字段里：`.mbti` 只显示这一个不透明字段，
/// 改动它的内部字段不会改变公开接口（改类型名会）。
pub struct Parser {
  inner : ParserState
}

///|
/// 解析器的全部可变状态。私有实现细节，不是可用 API。
struct ParserState {
  limits : Limits
  mut ctx : Ctx
  frames : Array[Frame]
  mut lex : LexKind
  mut num_state : NumState
  /// 已消费的绝对字节数。
  mut offset : Int
  mut total_bytes : Int
  mut node_count : Int
  mut finished : Bool
  mut events : Array[Event]
  /// 收到的全部原始字节，用于构造 `CompletedDocument`。
  raw : Array[Byte]
  /// 当前字符串已解码的内容。
  str_buf : StringBuilder
  /// 本次 `feed` 尚未交付的字符串增量。
  str_delta : StringBuilder
  /// 当前数字的原始词法。
  num_buf : StringBuilder
  /// 当前 token 的起始绝对偏移。
  mut token_start : Int
  /// 当前 token 已消费的字节数。
  mut token_bytes : Int
  /// 当前字符串是否是对象键。
  mut in_key : Bool
  /// 当前正在读取的值的路径。
  mut cur_path : Path
  /// UTF-8 待续字节（存 Int 以避免 Byte 转换）。
  utf8_pending : Array[Int]
  mut utf8_expected : Int
  mut utf8_start : Int
}

///|
/// 创建解析器。限制不合法时抛出 `InvalidLimits`。
///
/// ```mbt check
/// test {
///   let parser = Parser::new()
///   let events = parser.feed(b"{\"city\":")
///   inspect(events.length(), content="2")
/// }
/// ```
pub fn Parser::new(limits? : Limits) -> Parser raise ParseError {
  let limits = match limits {
    Some(l) => l
    None => Limits::strict()
  }
  validate_limits(
    max_depth=limits.max_depth,
    max_token_bytes=limits.max_token_bytes,
    max_nodes=limits.max_nodes,
    max_total_bytes=limits.max_total_bytes,
  )
  let inner : ParserState = {
    limits,
    ctx: RootStart,
    frames: [],
    lex: LexNormal,
    num_state: NumZero,
    offset: 0,
    total_bytes: 0,
    node_count: 0,
    finished: false,
    events: [],
    raw: [],
    str_buf: StringBuilder::new(),
    str_delta: StringBuilder::new(),
    num_buf: StringBuilder::new(),
    token_start: 0,
    token_bytes: 0,
    in_key: false,
    cur_path: Path::root(),
    utf8_pending: [],
    utf8_expected: 0,
    utf8_start: -1,
  }
  { inner, }
}

///|
/// 已消费的绝对字节数。
pub fn Parser::offset(self : Parser) -> Int {
  self.inner.offset
}

///|
/// 当前生效的资源限制。
pub fn Parser::limits(self : Parser) -> Limits {
  self.inner.limits
}

///|
/// 是否已经 `finish`（无论结果是完成、未完成还是取消）。
///
/// 解析出错后也会返回 `true`：错误使解析器进入终止状态。
pub fn Parser::is_finished(self : Parser) -> Bool {
  self.inner.finished
}

///|
/// 消费一段输入，返回本次产生的结构事件。
///
/// 空块不改变语义。任何错误都会使解析器进入终止状态：之后再次 `feed`
/// 或 `finish` 抛出 `AlreadyFinished`。
pub fn Parser::feed(
  self : Parser,
  bytes : Bytes,
) -> Array[Event] raise ParseError {
  if self.inner.finished {
    raise ParseError::AlreadyFinished(op="feed")
  }
  try self.feed_inner(bytes) catch {
    err => {
      self.inner.finished = true
      raise err
    }
  } noraise {
    events => events
  }
}

///|
/// `feed` 的实际实现；任何抛出都由 `feed` 统一转为终止状态。
fn Parser::feed_inner(
  self : Parser,
  bytes : Bytes,
) -> Array[Event] raise ParseError {
  let n = bytes.length()
  let remaining = self.inner.limits.max_total_bytes - self.inner.total_bytes
  let accepted = if n < remaining { n } else { remaining }
  for k in 0..<accepted {
    self.inner.raw.push(bytes[k])
  }
  self.inner.total_bytes += accepted
  self.inner.events = []
  let mut i = 0
  while i < accepted {
    let b = bytes[i].to_int()
    let pos = self.inner.offset
    let mut consumed = true
    match self.inner.lex {
      LexNormal => self.step_normal(b, pos)
      LexStr => self.step_str(b, pos)
      LexStrEscape => self.step_escape(b, pos)
      LexStrHex(count, acc) => self.step_hex(b, pos, count, acc)
      LexStrLowSlash(hi) => self.step_low_slash(b, pos, hi)
      LexStrLowU(hi) => self.step_low_u(b, pos, hi)
      LexStrLowHex(count, hi, acc) => self.step_low_hex(b, pos, count, hi, acc)
      LexNum => consumed = self.step_num(b, pos)
      LexLit(kind, matched) => self.step_lit(b, pos, kind, matched)
    }
    if consumed {
      i += 1
      self.inner.offset += 1
    }
  }
  if accepted < n {
    raise ParseError::LimitExceeded(
      kind=LimitKind::TotalBytes,
      pos=self.inner.offset,
      allowed=self.inner.limits.max_total_bytes,
      actual=self.inner.limits.max_total_bytes + 1,
    )
  }
  self.flush_string_delta()
  self.inner.events
}

///|
/// 结束输入并判断文档是否完整合法。
///
/// 返回 `(收尾事件, 结果)`：一个恰好以数字结尾的文档，它的 `ValueComplete`
/// 只有在调用 `finish` 时才能被确认，所以收尾事件必须一并交付。
///
/// 只有 `EndOfStream` 可能返回 `Completed`；取消或截断返回 `Aborted`。
///
/// ```mbt check
/// test {
///   let parser = Parser::new()
///   let _ = parser.feed(b"[1")
///   let (events, result) = parser.finish()
///   // 末尾数字只有在 finish 时才能被确认，收尾事件一并交付。
///   inspect(events.length(), content="1")
///   inspect(result is FinishResult::Incomplete(..), content="true")
/// }
/// ```
pub fn Parser::finish(
  self : Parser,
  reason? : EndReason,
) -> (Array[Event], FinishResult) raise ParseError {
  if self.inner.finished {
    raise ParseError::AlreadyFinished(op="finish")
  }
  self.inner.finished = true
  self.inner.events = []
  let reason = match reason {
    Some(r) => r
    None => EndOfStream
  }
  let result = match reason {
    EndOfStream => self.finish_normal()
    _ => FinishResult::Aborted(reason~)
  }
  (self.inner.events, result)
}

///|
/// 正常结束路径：补齐可终结的 token，检查语法栈与 UTF-8 残留。
fn Parser::finish_normal(self : Parser) -> FinishResult raise ParseError {
  if self.inner.utf8_expected > 0 {
    raise ParseError::InvalidUtf8(
      pos=self.inner.utf8_start,
      kind=Utf8ErrorKind::InvalidContinuation,
    )
  }
  match self.inner.lex {
    LexNum =>
      if self.num_is_terminable() {
        self.finalize_number()
      } else {
        return FinishResult::Incomplete(
          pos=self.inner.offset,
          expected="数字尚未写完",
        )
      }
    LexNormal => ()
    LexStr =>
      return FinishResult::Incomplete(
        pos=self.inner.offset,
        expected="字符串缺少结束引号",
      )
    LexStrEscape =>
      return FinishResult::Incomplete(
        pos=self.inner.offset,
        expected="转义序列未完成",
      )
    LexStrHex(_, _) =>
      return FinishResult::Incomplete(
        pos=self.inner.offset,
        expected="\\u 转义未完成",
      )
    LexStrLowSlash(_) | LexStrLowU(_) | LexStrLowHex(_, _, _) =>
      return FinishResult::Incomplete(
        pos=self.inner.offset,
        expected="代理对未完成",
      )
    LexLit(_, _) =>
      return FinishResult::Incomplete(
        pos=self.inner.offset,
        expected="字面量未完成",
      )
  }
  match self.inner.ctx {
    RootDone => {
      let text = @utf8.decode(Bytes::from_array(self.inner.raw)) catch {
        _ =>
          raise ParseError::InvalidUtf8(
            pos=0,
            kind=Utf8ErrorKind::InvalidLeadByte,
          )
      }
      FinishResult::Completed(
        CompletedDocument::new(text, self.inner.total_bytes),
      )
    }
    RootStart =>
      FinishResult::Incomplete(
        pos=self.inner.offset,
        expected="文档尚未开始",
      )
    ObjKeyOrEnd =>
      FinishResult::Incomplete(
        pos=self.inner.offset,
        expected="对象键或 '}'",
      )
    ObjKey =>
      FinishResult::Incomplete(pos=self.inner.offset, expected="对象键")
    ObjColon => FinishResult::Incomplete(pos=self.inner.offset, expected="':'")
    ObjValue | ArrValue | ArrValueOrEnd =>
      FinishResult::Incomplete(pos=self.inner.offset, expected="值")
    ObjCommaOrEnd =>
      FinishResult::Incomplete(pos=self.inner.offset, expected="',' 或 '}'")
    ArrCommaOrEnd =>
      FinishResult::Incomplete(pos=self.inner.offset, expected="',' 或 ']'")
  }
}

///|
/// 当前值应该出现的路径。
fn Parser::value_path(self : Parser) -> Path {
  match self.inner.frames.last() {
    None => Path::root()
    Some(frame) =>
      match frame.kind {
        Obj => frame.pending_path
        Arr => frame.path.child_index(frame.count)
      }
  }
}

///|
/// 一个子值完成后，把父级上下文推进到 `,` 或结束。
fn Parser::after_child(self : Parser) -> Unit {
  match self.inner.frames.last() {
    None => self.inner.ctx = RootDone
    Some(frame) => {
      frame.count += 1
      self.inner.ctx = match frame.kind {
        Obj => ObjCommaOrEnd
        Arr => ArrCommaOrEnd
      }
    }
  }
}

///|
/// 记录 token 字节数并检查单 token 限制。
fn Parser::bump_token(self : Parser, pos : Int) -> Unit raise ParseError {
  self.inner.token_bytes += 1
  if self.inner.token_bytes > self.inner.limits.max_token_bytes {
    raise ParseError::LimitExceeded(
      kind=LimitKind::TokenBytes,
      pos~,
      allowed=self.inner.limits.max_token_bytes,
      actual=self.inner.token_bytes,
    )
  }
}

///|
/// 把本次 `feed` 累积的字符串增量交付出去。
fn Parser::flush_string_delta(self : Parser) -> Unit {
  if self.inner.lex is LexStr &&
    !self.inner.in_key &&
    !self.inner.str_delta.is_empty() {
    self.inner.events.push(
      Event::StringDelta(
        path=self.inner.cur_path,
        text=self.inner.str_delta.to_string(),
        span=Span::new(self.inner.token_start, self.inner.offset),
      ),
    )
    self.inner.str_delta.reset()
  }
}
