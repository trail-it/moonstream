// 用 SDK 的真实 `StreamEvent` 值驱动适配器，并用 SDK 自己解析的 Json 对照。

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
test "mizchi/llm：字符串 id 映射到序号，两个调用互不干扰" {
  let adapter = @mizchi_llm_adapter.MizchiLlmAdapter::new(response_id="resp-1")
  let events = [
    @sdk.StreamEvent::MessageStart,
    @sdk.StreamEvent::ToolCallStart(id="call_a", name="create_ticket"),
    @sdk.StreamEvent::ToolCallDelta(id="call_a", input_delta="{\"title\":\"登"),
    @sdk.StreamEvent::ToolCallStart(id="call_b", name="send_mail"),
    @sdk.StreamEvent::ToolCallDelta(id="call_b", input_delta="{\"to\":\"a@b"),
    @sdk.StreamEvent::ToolCallDelta(id="call_a", input_delta="录失败\"}"),
    @sdk.StreamEvent::ToolCallDelta(id="call_b", input_delta=".c\"}"),
    @sdk.StreamEvent::ToolCallEnd(
      id="call_a",
      name="create_ticket",
      input=@json.parse("{\"title\":\"登录失败\"}"),
    ),
    @sdk.StreamEvent::ToolCallEnd(
      id="call_b",
      name="send_mail",
      input=@json.parse("{\"to\":\"a@b.c\"}"),
    ),
    @sdk.StreamEvent::MessageEnd(
      finish_reason=@sdk.FinishReason::ToolUse,
      usage=None,
    ),
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
            Some(@moonstream.FinishResult::Completed(doc)) =>
              documents.push(doc)
            Some(_) => fail("应当完成")
            None => ()
          }
        }
    }
  }
  inspect(delivered.join(","), content="$.title=登录失败,$.to=a@b.c")
  inspect(documents.length(), content="2")
  // id 与序号的映射稳定
  inspect(adapter.slot("call_a"), content="0")
  inspect(adapter.slot("call_b"), content="1")
  // 本库的结果与 SDK 自己解析出的 Json 一致
  inspect(
    documents[0].to_json().stringify(),
    content="{\"title\":\"登录失败\"}",
  )
  inspect(documents[1].to_json().stringify(), content="{\"to\":\"a@b.c\"}")
}

///|
test "mizchi/llm：Length 到达前不交付，Length 到达后标为截断" {
  let adapter = @mizchi_llm_adapter.MizchiLlmAdapter::new()
  let _ = adapter.apply(@sdk.StreamEvent::ToolCallStart(id="x", name="f"))
  let _ = adapter.apply(
    @sdk.StreamEvent::ToolCallDelta(id="x", input_delta="{}"),
  )
  inspect(
    adapter.apply(
      @sdk.StreamEvent::ToolCallEnd(id="x", name="f", input=@json.parse("{}")),
    )
    is @adapter.AdapterOutcome::Ignored,
    content="true",
  )
  match
    adapter.apply(
      @sdk.StreamEvent::MessageEnd(
        finish_reason=@sdk.FinishReason::Length,
        usage=None,
      ),
    ) {
    @adapter.AdapterOutcome::Updates(
      updates=[{ result: Some(@moonstream.FinishResult::Aborted(..)), .. }]
    ) => ()
    _ => fail("Length 必须产生 Aborted")
  }
}

///|
test "mizchi/llm：未结束的调用可以按截断收尾" {
  let adapter = @mizchi_llm_adapter.MizchiLlmAdapter::new()
  let _ = adapter.apply(
    @sdk.StreamEvent::ToolCallStart(id="call_a", name="create_ticket"),
  )
  let _ = adapter.apply(
    @sdk.StreamEvent::ToolCallDelta(id="call_a", input_delta="{\"title\":\"登"),
  )
  let (_, result) = adapter.finish_slot(
    0,
    reason=@moonstream.EndReason::Truncated,
  )
  inspect(result is @moonstream.FinishResult::Aborted(..), content="true")
}

///|
test "mizchi/llm：与工具无关的事件被忽略" {
  let adapter = @mizchi_llm_adapter.MizchiLlmAdapter::new()
  for
    event in [
      @sdk.StreamEvent::MessageStart,
      @sdk.StreamEvent::TextDelta("纯文本"),
      @sdk.StreamEvent::Error("boom"),
    ] {
    match adapter.apply(event) {
      @adapter.AdapterOutcome::Ignored => ()
      _ => fail("应当为 Ignored")
    }
  }
  inspect(adapter.session().call_count(), content="0")
}
