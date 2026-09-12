// 适配 `DC-Z-lab/moonllm@0.1.0`。
//
// 该 SDK 的 `ToolCallAccumulator` 把参数片段拼进 StringBuilder，等到
// `finish` 才给出完整字符串；`ToolCallDelta.arguments` 就是本库要消费的
// "参数文本片段"。本适配器把每个 `ToolCallDelta` 直接送进 Session，
// 于是同一个流的消费方不必再自己维护一套拼接与部分解析。
//
// 键映射：`ToolCallDelta.index`（该 choice 内的工具调用序号）→ `CallKey.index`，
// `choice` 固定为 0（该 SDK 的 `parse_stream_data` 只读取 choices[0]）。
//
// apply 在收到 StreamChunk.finish_reason 时自动收尾。
// 意外断流由调用方使用显式 Truncated / Cancelled 原因收尾。

///|
/// `moonllm` 流式 chunk 到 MoonStream 会话的适配器。
pub struct MoonllmAdapter {
  session : @session.Session
  response_id : String
  choice : Int
}

///|
/// 创建适配器。
pub fn MoonllmAdapter::new(
  response_id? : String,
  choice? : Int,
) -> MoonllmAdapter raise @session.SessionError {
  {
    session: @session.Session::new(),
    response_id: match response_id {
      Some(value) => value
      None => ""
    },
    choice: match choice {
      Some(value) => value
      None => 0
    },
  }
}

///|
/// 底层会话。
pub fn MoonllmAdapter::session(self : MoonllmAdapter) -> @session.Session {
  self.session
}

///|
/// 工具调用序号对应的调用键。
pub fn MoonllmAdapter::key(
  self : MoonllmAdapter,
  index : Int,
) -> @session.CallKey {
  @session.CallKey::new(response=self.response_id, choice=self.choice, index~)
}

///|
/// 处理一个流式 chunk。
///
/// 首个带 `id` / `name` 的片段会注册调用上下文；带 `arguments` 的片段被喂入解析器。
/// 文本增量与其它字段被忽略。
pub fn MoonllmAdapter::apply(
  self : MoonllmAdapter,
  chunk : @sdk.StreamChunk,
) -> @adapter.AdapterOutcome raise @session.SessionError {
  let updates = []
  for delta in chunk.tool_calls {
    let key = self.key(delta.index)
    // 总是尝试注册：首个片段建立上下文，后续片段的 id / name 若与已有值冲突，
    // Session 会报 CallIdConflict / CallNameConflict，而不是把两个调用拼在一起。
    self.session.open(key, id=delta.id, name=delta.name)
    match delta.arguments {
      Some(arguments) =>
        match self.session.feed(key, @utf8.encode(arguments)) {
          [] => ()
          events => updates.push(@adapter.CallUpdate::delta(key, events))
        }
      None => ()
    }
  }
  match chunk.finish_reason {
    Some(reason) => updates.append(self.finish_updates(reason.end_reason()))
    None => ()
  }
  if updates.is_empty() {
    @adapter.AdapterOutcome::Ignored
  } else {
    @adapter.AdapterOutcome::Updates(updates~)
  }
}

///|
fn String::end_reason(self : String) -> @moonstream.EndReason {
  match self {
    "stop" | "end_turn" | "tool_calls" | "tool_use" =>
      @moonstream.EndReason::EndOfStream
    _ => @moonstream.EndReason::Truncated
  }
}

///|
fn MoonllmAdapter::finish_updates(
  self : MoonllmAdapter,
  reason : @moonstream.EndReason,
) -> Array[@adapter.CallUpdate] {
  @adapter.finish_open(self.session, reason)
}

///|
/// 结束一个调用（例如收到 `finish_reason` 时）。
pub fn MoonllmAdapter::finish_call(
  self : MoonllmAdapter,
  index : Int,
  reason~ : @moonstream.EndReason,
) -> (Array[@moonstream.Event], @moonstream.FinishResult) raise @session.SessionError {
  self.session.finish(self.key(index), reason~)
}

///|
/// 结束所有仍在进行的调用，按注册顺序返回带收尾事件、结果或 failure 的更新。
pub fn MoonllmAdapter::finish_all(
  self : MoonllmAdapter,
  reason~ : @moonstream.EndReason,
) -> Array[@adapter.CallUpdate] {
  self.finish_updates(reason)
}
