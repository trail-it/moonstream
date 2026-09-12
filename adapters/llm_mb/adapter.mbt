// 适配 `marianoguerra/llm@0.1.1`（仓库 llm-mb）。
//
// 该 SDK 的事件模型把工具参数作为**文本增量**交付，其源码注释明确要求
// 消费者等到 `stream_finish` 才能拿到解析结果：
//
//   /// Arguments arrive as partial JSON TEXT — every provider streams them that
//   /// way — so a consumer that wants them parsed waits for `stream_finish`.
//
// 本适配器把 `ToolCallStart / ToolCallDelta / ToolCallEnd` 直接接到
// MoonStream 的 Session 上，让调用方在流还没结束时就能拿到逐字段事件。
//
// 键映射：`content_index`（该 SDK 的内容块下标）→ `CallKey.index`，`choice` 固定为 0。

///|
/// `marianoguerra/llm` 流式事件到 MoonStream 会话的适配器。
pub struct LlmMbAdapter {
  session : @session.Session
  response_id : String
}

///|
/// 创建适配器。`response_id` 用于构造稳定的调用键。
pub fn LlmMbAdapter::new(
  response_id? : String,
) -> LlmMbAdapter raise @session.SessionError {
  {
    session: @session.Session::new(),
    response_id: match response_id {
      Some(value) => value
      None => ""
    },
  }
}

///|
/// 底层会话，便于查询调用状态。
pub fn LlmMbAdapter::session(self : LlmMbAdapter) -> @session.Session {
  self.session
}

///|
/// 内容块下标对应的调用键。
pub fn LlmMbAdapter::key(
  self : LlmMbAdapter,
  content_index : Int,
) -> @session.CallKey {
  @session.CallKey::new(
    response=self.response_id,
    choice=0,
    index=content_index,
  )
}

///|
/// 处理一个 SDK 事件。
///
/// `ToolCallStart` 注册调用上下文，`ToolCallDelta` 喂入参数字节，
/// `ToolCallEnd` 只表示内容块结束；最终完整性由随后到达的 `Done(stop)` 决定。
pub fn LlmMbAdapter::apply(
  self : LlmMbAdapter,
  event : @llm.StreamEvent,
) -> @adapter.AdapterOutcome raise @session.SessionError {
  match event {
    @llm.StreamEvent::ToolCallStart(content_index~, id~, name~) => {
      self.session.open(self.key(content_index), id=Some(id), name=Some(name))
      @adapter.AdapterOutcome::Ignored
    }
    @llm.StreamEvent::ToolCallDelta(content_index~, delta~) =>
      delta_outcome(
        self.key(content_index),
        self.session.feed(self.key(content_index), @utf8.encode(delta)),
      )
    @llm.StreamEvent::ToolCallEnd(..) => @adapter.AdapterOutcome::Ignored
    @llm.StreamEvent::Done(stop~, ..) => self.finish_open(stop.end_reason())
    @llm.StreamEvent::Error(..) =>
      self.finish_open(@moonstream.EndReason::Truncated)
    _ => @adapter.AdapterOutcome::Ignored
  }
}

///|
fn @llm.StopReason::end_reason(self : @llm.StopReason) -> @moonstream.EndReason {
  match self {
    EndTurn | ToolUse => @moonstream.EndReason::EndOfStream
    MaxTokens | Errored => @moonstream.EndReason::Truncated
    Aborted => @moonstream.EndReason::Cancelled
  }
}

///|
fn delta_outcome(
  key : @session.CallKey,
  events : Array[@moonstream.Event],
) -> @adapter.AdapterOutcome {
  if events.is_empty() {
    @adapter.AdapterOutcome::Ignored
  } else {
    @adapter.AdapterOutcome::Updates(updates=[
      @adapter.CallUpdate::delta(key, events),
    ])
  }
}

///|
fn LlmMbAdapter::finish_open(
  self : LlmMbAdapter,
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
pub fn LlmMbAdapter::finish_call(
  self : LlmMbAdapter,
  content_index : Int,
  reason~ : @moonstream.EndReason,
) -> (Array[@moonstream.Event], @moonstream.FinishResult) raise @session.SessionError {
  self.session.finish(self.key(content_index), reason~)
}
