// 消费者视角的集成测试：像外部用户一样只通过公开 API 使用本库。
// 这里不 import 任何内部实现，用于验证公开契约确实可用。

///|
/// 模拟一条工具调用参数流的消费路径：分块喂入 → 观察事件 → 判断可交付性。
fn consume(
  chunks : Array[Bytes],
) -> (Array[String], @moonstream.FinishResult) raise {
  let parser = @moonstream.Parser::new()
  let log = []
  for chunk in chunks {
    for event in parser.feed(chunk) {
      match event {
        @moonstream.Event::ValueComplete(path~, value~, ..) =>
          log.push("\{path.to_string()}=\{describe(value)}")
        _ => ()
      }
    }
  }
  let (tail, result) = parser.finish()
  for event in tail {
    match event {
      @moonstream.Event::ValueComplete(path~, value~, ..) =>
        log.push("\{path.to_string()}=\{describe(value)}")
      _ => ()
    }
  }
  (log, result)
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
test "工具调用参数：逐字段交付" {
  let source = "{\"tool\":\"create_ticket\",\"args\":{\"title\":\"登录失败\",\"priority\":3}}"
  let bytes = @utf8.encode(source)
  let (log, result) = consume([bytes])
  inspect(
    log.join(","),
    content="$.tool=create_ticket,$.args.title=登录失败,$.args.priority=3",
  )
  match result {
    @moonstream.FinishResult::Completed(doc) =>
      inspect(doc.to_string(), content=source)
    _ => fail("应当完成")
  }
}

///|
test "流被截断时预览保留但不可交付" {
  let bytes = @utf8.encode("{\"args\":{\"title\":\"登录失败\"")
  let parser = @moonstream.Parser::new()
  let events = parser.feed(bytes)
  let seen = []
  for event in events {
    match event {
      @moonstream.Event::ValueComplete(path~, value~, ..) =>
        seen.push("\{path.to_string()}=\{describe(value)}")
      _ => ()
    }
  }
  inspect(seen.join(","), content="$.args.title=登录失败")
  let (_, result) = parser.finish(reason=@moonstream.EndReason::Truncated)
  inspect(result is @moonstream.FinishResult::Aborted(..), content="true")
}

///|
test "任意分块不改变交付字段" {
  let source = "{\"a\":\"上海\",\"b\":[1,2],\"c\":true}"
  let bytes = @utf8.encode(source)
  let (base, _) = consume([bytes])
  for i in 0..<=bytes.length() {
    let chunks = [
      Bytes::from_array(bytes[0:i].to_array()),
      Bytes::from_array(bytes[i:bytes.length()].to_array()),
    ]
    let (log, result) = consume(chunks)
    inspect(log.join(","), content=base.join(","))
    inspect(result is @moonstream.FinishResult::Completed(_), content="true")
  }
}
