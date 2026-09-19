// 用 SDK 的真实 `StreamChunk` / `ToolCallDelta` 值驱动适配器。

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
fn collect_outcome(outcome : @adapter.AdapterOutcome) -> Array[String] {
  let out = []
  for update in outcome.updates() {
    out.append(collect(update.events))
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
    @moonstream.FinishResult::Aborted(reason~) =>
      "<aborted:\{Debug::to_repr(reason)}>"
  }
}

///|
/// 构造一个工具调用片段。
fn delta(
  index : Int,
  id : String?,
  name : String?,
  arguments : String?,
) -> @sdk.ToolCallDelta {
  { index, id, name, arguments, }
}

///|
test "moonllm：两个调用交错，字段逐个交付" {
  let adapter = @moonllm_adapter.MoonllmAdapter::new(response_id="chatcmpl-1")
  // 这些值全部来自 SDK 的公开类型 @sdk.StreamChunk / @sdk.ToolCallDelta
  let chunks : Array[@sdk.StreamChunk] = [
    {
      content: Some("先说明一下"),
      tool_calls: [
        delta(
          0,
          Some("call_a"),
          Some("create_ticket"),
          Some("{\"title\":\"登"),
        ),
      ],
      finish_reason: None,
    },
    {
      content: None,
      tool_calls: [
        delta(1, Some("call_b"), Some("send_mail"), Some("{\"to\":\"a@b")),
      ],
      finish_reason: None,
    },
    {
      content: None,
      tool_calls: [delta(0, None, None, Some("录失败\"}"))],
      finish_reason: None,
    },
    {
      content: None,
      tool_calls: [delta(1, None, None, Some(".c\"}"))],
      finish_reason: None,
    },
  ]
  let delivered = []
  for chunk in chunks {
    delivered.append(collect_outcome(adapter.apply(chunk)))
  }
  inspect(delivered.join(","), content="$.title=登录失败,$.to=a@b.c")
  // 该 SDK 没有"调用结束"事件，由调用方在收到 finish_reason 时收尾
  let results = adapter.finish_all(reason=@moonstream.EndReason::EndOfStream)
  let documents = []
  for entry in results {
    match entry.result {
      Some(result) => documents.push(document_of(result))
      None => fail("finish_all 必须返回结束结果")
    }
  }
  inspect(
    documents.join(" | "),
    content="{\"title\":\"登录失败\"} | {\"to\":\"a@b.c\"}",
  )
  let session = adapter.session()
  debug_inspect(session.call_id(adapter.key(0)), content="Some(\"call_a\")")
  debug_inspect(
    session.call_name(adapter.key(1)),
    content="Some(\"send_mail\")",
  )
  inspect(session.is_finished(adapter.key(0)), content="true")
}

///|
test "moonllm：不同 index 不会互相覆盖" {
  let adapter = @moonllm_adapter.MoonllmAdapter::new(response_id="r")
  let _ = adapter.apply({
    content: None,
    tool_calls: [
      delta(0, Some("call_a"), Some("a"), Some("[1,")),
      delta(1, Some("call_b"), Some("b"), Some("[2,")),
    ],
    finish_reason: None,
  })
  let _ = adapter.apply({
    content: None,
    tool_calls: [delta(0, None, None, Some("3]"))],
    finish_reason: None,
  })
  let _ = adapter.apply({
    content: None,
    tool_calls: [delta(1, None, None, Some("4]"))],
    finish_reason: None,
  })
  let documents = []
  for entry in adapter.finish_all(reason=@moonstream.EndReason::EndOfStream) {
    match entry.result {
      Some(result) => documents.push(document_of(result))
      None => fail("finish_all 必须返回结束结果")
    }
  }
  inspect(documents.join(" | "), content="[1,3] | [2,4]")
}

///|
test "moonllm：同一 chunk 的事件保留各自 CallKey" {
  let adapter = @moonllm_adapter.MoonllmAdapter::new(response_id="r")
  let outcome = adapter.apply({
    content: None,
    tool_calls: [
      delta(0, Some("a"), Some("f"), Some("{\"x\":1}")),
      delta(1, Some("b"), Some("g"), Some("{\"x\":2}")),
    ],
    finish_reason: None,
  })
  match outcome {
    @adapter.AdapterOutcome::Updates(updates=[first, second]) => {
      inspect(first.key == adapter.key(0), content="true")
      inspect(second.key == adapter.key(1), content="true")
      inspect(collect(first.events).join(","), content="$.x=1")
      inspect(collect(second.events).join(","), content="$.x=2")
    }
    _ => fail("两个调用应产生两个带键的更新")
  }
}

///|
test "moonllm：finish_all 保留末尾数字的收尾事件" {
  let adapter = @moonllm_adapter.MoonllmAdapter::new()
  let _ = adapter.apply({
    content: None,
    tool_calls: [delta(0, Some("a"), Some("f"), Some("12"))],
    finish_reason: None,
  })
  match adapter.finish_all(reason=@moonstream.EndReason::EndOfStream) {
    [{ events, result: Some(@moonstream.FinishResult::Completed(_)), .. }] =>
      inspect(collect(events).join(","), content="$=12")
    _ => fail("应保留根数字的 ValueComplete")
  }
}

///|
test "moonllm：length 自动结束且不可交付" {
  let adapter = @moonllm_adapter.MoonllmAdapter::new()
  let outcome = adapter.apply({
    content: None,
    tool_calls: [delta(0, Some("a"), Some("f"), Some("{}"))],
    finish_reason: Some("length"),
  })
  match outcome {
    @adapter.AdapterOutcome::Updates(updates=[_, finished]) =>
      inspect(
        finished.result is Some(@moonstream.FinishResult::Aborted(..)),
        content="true",
      )
    _ => fail("最终 chunk 应包含增量与结束更新")
  }
}

///|
test "moonllm：id 冲突会被发现" {
  let adapter = @moonllm_adapter.MoonllmAdapter::new(response_id="r")
  let _ = adapter.apply({
    content: None,
    tool_calls: [delta(0, Some("call_a"), Some("f"), Some("{"))],
    finish_reason: None,
  })
  let outcome = try {
    let _ = adapter.apply({
      content: None,
      tool_calls: [delta(0, Some("call_b"), None, Some("}"))],
      finish_reason: None,
    })
    "no error"
  } catch {
    @session.SessionError::CallIdConflict(..) => "CallIdConflict"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(outcome, content="CallIdConflict")
}

///|
test "moonllm：只有文本增量时返回 Ignored" {
  let adapter = @moonllm_adapter.MoonllmAdapter::new()
  let outcome = adapter.apply({
    content: Some("纯文本"),
    tool_calls: [],
    finish_reason: None,
  })
  match outcome {
    @adapter.AdapterOutcome::Ignored => inspect("ignored", content="ignored")
    _ => fail("应当为 Ignored")
  }
}
