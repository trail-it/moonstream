// 对抗性用例：这些输入专门用来击穿转义、数字与空白处理的边界。

///|
test "转义后的键名与字面键名视为同一个键" {
  // \u0061 就是 'a'，因此这是重复键
  assert_error_kind("{\"a\":1,\"\\u0061\":2}", "DuplicateKey")
  // 不同层级互不影响
  let (_, result) = parse_whole("{\"a\":{\"a\":1},\"b\":2}")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"a\":{\"a\":1},\"b\":2}")
}

///|
test "空键与含转义引号的键" {
  let (events, result) = parse_whole("{\"\":1,\"a\\\"b\":2}")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"\":1,\"a\\\"b\":2}")
  let names = []
  for event in events {
    match event {
      @moonstream.Event::KeyComplete(name~, ..) => names.push(name)
      _ => ()
    }
  }
  inspect(names.length(), content="2")
  inspect(names[0], content="")
  inspect(names[1], content="a\"b")
}

///|
test "字符串里的 \\u0000 是合法字符" {
  let (events, result) = parse_whole("\"a\\u0000b\"")
  let _ = expect_completed(result)
  let mut text = ""
  for event in events {
    match event {
      @moonstream.Event::ValueComplete(
        value=@moonstream.LeafValue::String(s),
        ..
      ) => text = s
      _ => ()
    }
  }
  inspect(text.length(), content="3")
  inspect(text[1].to_int(), content="0")
}

///|
test "数字的极端合法形式" {
  let cases = [
    "-0", "-0.0", "1E+002", "1e-002", "0e0", "-0e0", "123456789012345678901234567890e-9",
  ]
  for source in cases {
    let (_, result) = parse_whole(source)
    let doc = expect_completed(result)
    inspect(doc.to_string(), content=source)
  }
}

///|
test "各种空白都可以分隔 token" {
  let cases = [
    "{\r\n\t\"a\"\u{20}:\u{20}1\r\n}", "[1,\r2,\t3,\n4]", "  \t\r\n  true  \t\r\n  ",
  ]
  for source in cases {
    let (_, result) = parse_whole(source)
    let doc = expect_completed(result)
    inspect(doc.to_string(), content=source)
  }
}

///|
test "BOM 不是合法 JSON 起始，必须拒绝" {
  // U+FEFF 的 UTF-8 是 EF BB BF
  let err = expect_parse_error_bytes([0xEF, 0xBB, 0xBF, b'{', b'}'])
  match err {
    @moonstream.ParseError::InvalidSyntax(..) => inspect("ok", content="ok")
    _ => fail("BOM 应当被拒绝")
  }
}

///|
test "深度正好等于上限时通过，超过一个即失败" {
  let limits = @moonstream.Limits::new(max_depth=5)
  let parser = @moonstream.Parser::new(limits~)
  let _ = parser.feed(b"[[[[[1]]]]]")
  let (_, result) = parser.finish()
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
  let over = try {
    let parser = @moonstream.Parser::new(limits~)
    let _ = parser.feed(b"[[[[[[1]]]]]]")
    false
  } catch {
    @moonstream.ParseError::LimitExceeded(kind=@moonstream.LimitKind::Depth, ..) =>
      true
    _ => false
  } noraise {
    _ => false
  }
  inspect(over, content="true")
}

///|
test "单 token 字节限制按字节而不是字符计数" {
  // 每个汉字 3 字节；"中" 连引号共 5 字节
  let limits = @moonstream.Limits::new(max_token_bytes=5)
  let parser = @moonstream.Parser::new(limits~)
  let _ = parser.feed(utf8_bytes("\"中\""))
  let (_, result) = parser.finish()
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
  let over = try {
    let parser = @moonstream.Parser::new(limits~)
    let _ = parser.feed(utf8_bytes("\"中中\""))
    false
  } catch {
    @moonstream.ParseError::LimitExceeded(
      kind=@moonstream.LimitKind::TokenBytes,
      ..
    ) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(over, content="true")
}

///|
test "对抗性样本的分块不变性" {
  let samples = [
    "{\"a\\\"b\":\"x\\u0000y\",\"\\u4e2d\":[1e+002,-0.0]}", "{\"\":{},\"k\":[[[]]]}",
    "[\"\\uD83D\\uDE00\",\"\\ud83d\\ude00\"]",
  ]
  for sample in samples {
    let bytes = utf8_bytes(sample)
    let (base_events, base_result) = parse_whole(sample)
    let base_doc = expect_completed(base_result)
    let base_render = render_events(normalize_events(base_events))
    for split in all_two_way_splits(bytes) {
      let (events, result) = parse_chunks(split)
      let doc = expect_completed(result)
      inspect(doc.to_string(), content=base_doc.to_string())
      inspect(render_events(normalize_events(events)), content=base_render)
    }
  }
}

///|
test "代理对的大小写十六进制写法等价" {
  // 文档文本保留原始转义；解码后的值在事件里
  let (upper_events, upper) = parse_whole("\"\\uD83D\\uDE00\"")
  let (lower_events, lower) = parse_whole("\"\\ud83d\\ude00\"")
  inspect(expect_completed(upper).to_string(), content="\"\\uD83D\\uDE00\"")
  inspect(expect_completed(lower).to_string(), content="\"\\ud83d\\ude00\"")
  let decode = (events : Array[@moonstream.Event]) => {
    let mut text = ""
    for event in events {
      match event {
        @moonstream.Event::ValueComplete(
          value=@moonstream.LeafValue::String(s),
          ..
        ) => text = s
        _ => ()
      }
    }
    text
  }
  inspect(decode(upper_events), content="😀")
  inspect(decode(lower_events), content="😀")
}
