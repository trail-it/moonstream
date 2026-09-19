// 适配 `mizchi/llm@0.3.1`——生态里下载量最高的 MoonBit LLM 客户端。
//
// 该 SDK 的流式工具调用同样以文本增量交付参数：
//
//   ToolCallStart(id~ : String, name~ : String)
//   ToolCallDelta(id~ : String, input_delta~ : String)
//   ToolCallEnd(id~ : String, name~ : String, input~ : Json)
//
// 它用**字符串 id** 标识调用，而 MoonStream 的 `CallKey` 用整数序号。
// 本适配器按 id 首次出现的顺序分配序号，因此同一条流里 id 与序号一一对应；
// `ToolCallEnd` 携带的 `input` 是 SDK 自己解析好的 Json，可用来对照本库的结果。

///|
/// `mizchi/llm` 流式事件到 MoonStream 会话的适配器。
pub struct MizchiLlmAdapter {
  session : @session.Session
  response_id : String
  ids : Array[String]
}

///|
/// 创建适配器。
pub fn MizchiLlmAdapter::new(
  response_id? : String,
) -> MizchiLlmAdapter raise @session.SessionError {
  {
    session: @session.Session::new(),
    response_id: match response_id {
      Some(value) => value
      None => ""
    },
    ids: [],
  }
}

///|
/// 底层会话。
pub fn MizchiLlmAdapter::session(self : MizchiLlmAdapter) -> @session.Session {
  self.session
}

///|
/// 字符串 id 对应的整数序号（首次出现时分配）。
pub fn MizchiLlmAdapter::slot(self : MizchiLlmAdapter, id : String) -> Int {
  for index, known in self.ids {
    if known == id {
      return index
    }
  }
  self.ids.push(id)
  self.ids.length() - 1
}

///|
/// 调用键。
pub fn MizchiLlmAdapter::key(
  self : MizchiLlmAdapter,
  slot : Int,
) -> @session.CallKey {
  @session.CallKey::new(response=self.response_id, choice=0, index=slot)
}

///|
/// 处理一个 SDK 事件。
pub fn MizchiLlmAdapter::apply(
  self : MizchiLlmAdapter,
  event : @sdk.StreamEvent,
) -> @adapter.AdapterOutcome raise @session.SessionError {
  match event {
    @sdk.StreamEvent::ToolCallStart(id~, name~) => {
      self.session.open(self.key(self.slot(id)), id=Some(id), name=Some(name))
      @adapter.AdapterOutcome::Ignored
    }
    @sdk.StreamEvent::ToolCallDelta(id~, input_delta~) => {
      let key = self.key(self.slot(id))
      self.session.open(key, id=Some(id))
      let events = self.session.feed_text(key, input_delta)
      if events.is_empty() {
        @adapter.AdapterOutcome::Ignored
      } else {
        @adapter.AdapterOutcome::Updates(updates=[
          @adapter.CallUpdate::delta(key, events),
        ])
      }
    }
    @sdk.StreamEvent::ToolCallEnd(id~, name~, ..) => {
      self.session.open(self.key(self.slot(id)), id=Some(id), name=Some(name))
      @adapter.AdapterOutcome::Ignored
    }
    @sdk.StreamEvent::MessageEnd(finish_reason~, ..) =>
      self.finish_open(finish_reason.end_reason())
    @sdk.StreamEvent::Error(_) =>
      self.finish_open(@moonstream.EndReason::Truncated)
    _ => @adapter.AdapterOutcome::Ignored
  }
}

///|
fn @sdk.FinishReason::end_reason(
  self : @sdk.FinishReason,
) -> @moonstream.EndReason {
  match self {
    Stop | ToolUse => @moonstream.EndReason::EndOfStream
    Length | ContentFilter | Error | Unknown(_) =>
      @moonstream.EndReason::Truncated
  }
}

///|
fn MizchiLlmAdapter::finish_open(
  self : MizchiLlmAdapter,
  reason : @moonstream.EndReason,
) -> @adapter.AdapterOutcome {
  let updates = @adapter.finish_open(self.session, reason)
  if updates.is_empty() {
    @adapter.AdapterOutcome::Ignored
  } else {
    @adapter.AdapterOutcome::Updates(updates~)
  }
}

///|
/// 在没有收到 `ToolCallEnd` 的情况下结束某个调用。
pub fn MizchiLlmAdapter::finish_slot(
  self : MizchiLlmAdapter,
  slot : Int,
  reason~ : @moonstream.EndReason,
) -> (Array[@moonstream.Event], @moonstream.FinishResult) raise @session.SessionError {
  self.session.finish(self.key(slot), reason~)
}
