// 用 SDK 的真实 `StreamEvent` 值驱动适配器。

///|
/// 把完成事件收成 `路径=值` 文本。
fn collect(events : Array[@moonstream.Event]) -> Array[String] {
  let out = []
  for event in events {
    match event {
      @moonstream.Event::ValueComplete(path~, value~, ..) =>
        out.push("\{path.to_string()}=\{describe(value)}")
      _ => ()
    }
  }
  out
}

///|
fn describe(value : @moonstream.LeafValue) -> String {
  match value {
    @moonstream.LeafValue::Null => "null"
    @moonstream.LeafValue::Bool(b) => b.to_string()
    @moonstream.LeafValue::Number(n) => n.lexeme()
    @moonstream.LeafValue::String(s) => s
  }
}

///|
fn document_of(result : @moonstream.FinishResult) -> String {
  match result {
    @moonstream.FinishResult::Completed(doc) => doc.to_string()
    @moonstream.FinishResult::Incomplete(pos~, expected~) =>
      "<incomplete:\{pos}:\{expected}>"
    @moonstream.FinishResult::Aborted(reason~) => "<aborted:\{to_repr(reason)}>"
  }
}

///|
test "llm-mb：两个 tool call 交错，字段逐个交付" {
  let adapter = @llm_mb_adapter.LlmMbAdapter::new(response_id="resp-1")
  // 这些值全部来自 SDK 的公开类型 @llm.StreamEvent
  let events = [
    @llm.StreamEvent::Start(model="gpt-4o"),
    @llm.StreamEvent::ToolCallStart(
      content_index=0,
      id="call_a",
      name="create_ticket",
    ),
    @llm.StreamEvent::ToolCallDelta(content_index=0, delta="{\"title\":\"登"),
    @llm.StreamEvent::ToolCallStart(
      content_index=1,
      id="call_b",
      name="send_mail",
    ),
    @llm.StreamEvent::ToolCallDelta(content_index=1, delta="{\"to\":\"a@b"),
    @llm.StreamEvent::ToolCallDelta(content_index=0, delta="录失败\"}"),
    @llm.StreamEvent::ToolCallDelta(content_index=1, delta=".c\"}"),
    @llm.StreamEvent::ToolCallEnd(content_index=0),
    @llm.StreamEvent::ToolCallEnd(content_index=1),
    @llm.StreamEvent::Done(stop=@llm.StopReason::ToolUse, usage=None),
    @llm.StreamEvent::Error(message="与参数无关的事件"),
  ]
  let delivered = []
  let documents = []
  for event in events {
    match adapter.apply(event) {
      @adapter.AdapterOutcome::Ignored => ()
      @adapter.AdapterOutcome::Updates(updates~) =>
        for update in updates {
          delivered.append(collect(update.events))
          match update.result {
            Some(result) => documents.push(document_of(result))
            None => ()
          }
        }
    }
  }
  inspect(delivered.join(","), content="$.title=登录失败,$.to=a@b.c")
  inspect(
    documents.join(" | "),
    content="{\"title\":\"登录失败\"} | {\"to\":\"a@b.c\"}",
  )
  // 两个调用在会话里始终是两个独立对象
  let session = adapter.session()
  debug_inspect(session.call_id(adapter.key(0)), content="Some(\"call_a\")")
  debug_inspect(session.call_id(adapter.key(1)), content="Some(\"call_b\")")
  inspect(session.is_finished(adapter.key(0)), content="true")
  inspect(session.is_finished(adapter.key(1)), content="true")
}

///|
test "llm-mb：截断的调用不会产生结果对象" {
  let adapter = @llm_mb_adapter.LlmMbAdapter::new()
  let _ = adapter.apply(
    @llm.StreamEvent::ToolCallStart(
      content_index=0,
      id="call_a",
      name="create_ticket",
    ),
  )
  let outcome = adapter.apply(
    @llm.StreamEvent::ToolCallDelta(content_index=0, delta="{\"title\":\"登"),
  )
  inspect(outcome.updates()[0].events.length(), content="3")
  // 用截断原因结束
  let (_, result) = adapter.finish_call(
    0,
    reason=@moonstream.EndReason::Truncated,
  )
  inspect(result is @moonstream.FinishResult::Aborted(..), content="true")
}

///|
test "llm-mb：语法完整但 MaxTokens 仍不可交付" {
  let adapter = @llm_mb_adapter.LlmMbAdapter::new()
  let _ = adapter.apply(
    @llm.StreamEvent::ToolCallStart(content_index=0, id="x", name="f"),
  )
  let _ = adapter.apply(
    @llm.StreamEvent::ToolCallDelta(content_index=0, delta="{}"),
  )
  let _ = adapter.apply(@llm.StreamEvent::ToolCallEnd(content_index=0))
  match
    adapter.apply(
      @llm.StreamEvent::Done(stop=@llm.StopReason::MaxTokens, usage=None),
    ) {
    @adapter.AdapterOutcome::Updates(
      updates=[{ result: Some(@moonstream.FinishResult::Aborted(..)), .. }]
    ) => ()
    _ => fail("MaxTokens 必须产生 Aborted")
  }
}

///|
test "llm-mb：没有起始上下文就喂入增量会报错" {
  let adapter = @llm_mb_adapter.LlmMbAdapter::new()
  let outcome = try {
    let _ = adapter.apply(
      @llm.StreamEvent::ToolCallDelta(content_index=7, delta="{}"),
    )
    "no error"
  } catch {
    @session.SessionError::UnknownCall(..) => "UnknownCall"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(outcome, content="UnknownCall")
}
