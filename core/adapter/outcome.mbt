// SDK 无关的适配层支持类型。
//
// 具体 SDK 的适配代码在 workspace 成员里（adapters/llm_mb、adapters/mizchi_llm、
// adapters/moonllm），它们各自只依赖对应的 SDK，因此不会把任何 SDK 依赖带进主库。

///|
/// 一个工具调用在本次 SDK 事件中产生的更新。
///
/// `key` 让消费者把事件路由到正确的预览树；`result` 只在该调用已经根据
/// SDK 的终止原因完成收尾时出现。
pub(all) struct CallUpdate {
  key : @session.CallKey
  events : Array[@moonstream.Event]
  result : @moonstream.FinishResult?
  /// 本次收尾失败的原始错误；失败时 result 为 None。
  failure : @session.SessionError?
} derive(Eq, ToJson, Debug)

///|
/// 构造仍在进行中的调用更新。
pub fn CallUpdate::delta(
  key : @session.CallKey,
  events : Array[@moonstream.Event],
) -> CallUpdate {
  { key, events, result: None, failure: None }
}

///|
/// 构造已经结束的调用更新，保留 `finish` 产生的收尾事件。
pub fn CallUpdate::finished(
  key : @session.CallKey,
  events : Array[@moonstream.Event],
  result : @moonstream.FinishResult,
) -> CallUpdate {
  { key, events, result: Some(result), failure: None }
}

///|
/// 逐调用收尾；一个调用的错误不会阻止后续调用完成。
pub fn finish_open(
  session : @session.Session,
  reason : @moonstream.EndReason,
) -> Array[CallUpdate] {
  let updates = []
  for key in session.open_calls() {
    try session.finish(key, reason~) catch {
      error =>
        updates.push({ key, events: [], result: None, failure: Some(error) })
    } noraise {
      (events, result) =>
        updates.push(CallUpdate::finished(key, events, result))
    }
  }
  updates
}

///|
/// 适配层处理一个 SDK 事件后的结果。
pub(all) enum AdapterOutcome {
  /// 该事件没有产生工具参数状态变化。
  Ignored
  /// 一个 SDK 事件可能同时更新或结束多个工具调用。
  Updates(updates~ : Array[CallUpdate])
} derive(Eq, ToJson, Debug)

///|
/// 本次产生的、带调用身份的更新（`Ignored` 时为空）。
pub fn AdapterOutcome::updates(self : AdapterOutcome) -> Array[CallUpdate] {
  match self {
    Ignored => []
    Updates(updates~) => updates
  }
}
