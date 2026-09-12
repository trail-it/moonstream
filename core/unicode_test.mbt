// Unicode 与转义：跨块码元、代理对、非法序列。

///|
test "标准转义序列" {
  let source = "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\""
  let (events, result) = parse_whole(source)
  let doc = expect_completed(result)
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
  inspect(text, content="\"\\/\u{8}\u{c}\n\r\t")
  inspect(doc.to_string(), content=source)
}

///|
test "\\u 转义与代理对" {
  let (events, result) = parse_whole("\"\\u0041\\u00e9\\u4e2d\\uD83D\\uDE00\"")
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
  inspect(text, content="Aé中😀")
}

///|
test "1/2/3/4 字节 UTF-8 全覆盖" {
  // U+0041（1 字节）、U+00E9（2 字节）、U+4E2D（3 字节）、U+10348（4 字节）
  let source = "\"Aé中𐍈\""
  let bytes = utf8_bytes(source)
  let parser = @moonstream.Parser::new()
  let mut text = ""
  for i in 0..<bytes.length() {
    for event in parser.feed(slice_bytes(bytes, i, i + 1)) {
      match event {
        @moonstream.Event::ValueComplete(
          value=@moonstream.LeafValue::String(s),
          ..
        ) => text = s
        _ => ()
      }
    }
  }
  inspect(text, content="Aé中𐍈")
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content=source)
}

///|
test "高位代理之后必须紧跟 \\u 低位代理" {
  // 高位代理后接普通字符
  assert_error_kind("{\"a\":\"\\uD800x\"}", "InvalidUnicodeEscape")
  // 高位代理后接了 `\` 但不是 `u`
  assert_error_kind("{\"a\":\"\\uD800\\x\"}", "InvalidUnicodeEscape")
  // 低位代理的十六进制非法
  assert_error_kind("{\"a\":\"\\uD800\\u00zz\"}", "InvalidUnicodeEscape")
}

///|
test "合法首字节之后出现非法续字节" {
  let cases : Array[Array[Byte]] = [
    [b'"', 0xE4, b'A', b'"'],
    [b'"', 0xF0, 0x9F, b'A', b'"'],
  ]
  for bytes in cases {
    let err = expect_parse_error_bytes(Bytes::from_array(bytes))
    match err {
      @moonstream.ParseError::InvalidUtf8(..) => inspect("ok", content="ok")
      _ => fail("应当为 InvalidUtf8")
    }
  }
}

///|
test "四字节字符跨四个输入块" {
  let bytes = utf8_bytes("\"𐍈\"")
  let parser = @moonstream.Parser::new()
  let mut text = ""
  let mut deltas = 0
  for i in 0..<bytes.length() {
    for event in parser.feed(slice_bytes(bytes, i, i + 1)) {
      match event {
        @moonstream.Event::StringDelta(text=delta, ..) => {
          text = text + delta
          deltas = deltas + 1
        }
        @moonstream.Event::ValueComplete(
          value=@moonstream.LeafValue::String(s),
          ..
        ) => text = s
        _ => ()
      }
    }
  }
  inspect(text, content="𐍈")
  inspect(deltas, content="1")
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="\"𐍈\"")
}

///|
test "键名中的中文与转义" {
  let (events, result) = parse_whole("{\"\\u4e2d\\u6587\":\"值\"}")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"\\u4e2d\\u6587\":\"值\"}")
  inspect(
    render_events(events),
    content=(
      #|{$@0-1 | key:中文@1-15 | delta$.中文=值@16-20 | value$.中文=值@16-21 | }$@21-22
    ),
  )
}

///|
test "字符串内的括号与转义引号按词法处理" {
  let (events, result) = parse_whole("{\"a\":\"}{]\\\"[\"}")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"a\":\"}{]\\\"[\"}")
  inspect(
    render_events(events),
    content=(
      #|{$@0-1 | key:a@1-4 | delta$.a=}{]"[@5-12 | value$.a=}{]"[@5-13 | }$@13-14
    ),
  )
}

///|
test "未转义控制字符必须失败" {
  let err = expect_parse_error_bytes([b'"', 0x01, b'"'])
  match err {
    @moonstream.ParseError::InvalidEscape(..) => inspect("ok", content="ok")
    _ => fail("应当为 InvalidEscape")
  }
}

///|
test "孤立代理项与非法码点必须失败" {
  let cases = [
    "\"\\uD800\"", "\"\\uDC00\"", "\"\\uD800\\u0041\"", "\"\\uD800\\uD800\"",
  ]
  for source in cases {
    let _ = expect_parse_error(source)
  }
}

///|
test "非法 UTF-8 序列必须失败" {
  let cases : Array[Array[Byte]] = [
    [b'"', 0x80, b'"'],
    [b'"', 0xBF, b'"'],
    [b'"', 0xC0, 0xAF, b'"'],
    [b'"', 0xC1, 0xBF, b'"'],
    [b'"', 0xE0, 0x80, 0x80, b'"'],
    [b'"', 0xED, 0xA0, 0x80, b'"'],
    [b'"', 0xF0, 0x80, 0x80, 0x80, b'"'],
    [b'"', 0xF4, 0x90, 0x80, 0x80, b'"'],
    [b'"', 0xF5, 0x80, 0x80, 0x80, b'"'],
    [b'"', 0xE4, b'"'],
    [b'"', 0xE4, 0xB8, b'"'],
  ]
  for bytes in cases {
    let _ = expect_parse_error_bytes(Bytes::from_array(bytes))
  }
}

///|
test "转义序列未完成时 finish 返回 Incomplete" {
  let cases = [
    "\"abc", // 字符串未闭合
     "\"abc\\", // 反斜杠之后
     "\"abc\\u12", // \u 只读到 2 位
     "\"abc\\uD800", // 高位代理之后
     "\"abc\\uD800\\", // 高位代理之后期待 u
     "\"abc\\uD800\\u12", // 低位代理只读到 2 位
  ]
  for source in cases {
    let (_, result) = parse_whole(source)
    match result {
      @moonstream.FinishResult::Incomplete(..) =>
        inspect("incomplete", content="incomplete")
      _ => fail("\{source} 应当为 Incomplete")
    }
  }
}

///|
test "结束于未收齐的 UTF-8 序列必须失败" {
  let parser = @moonstream.Parser::new()
  let _ = parser.feed([b'"', 0xE4, 0xB8])
  let outcome = try {
    let _ = parser.finish()
    false
  } catch {
    @moonstream.ParseError::InvalidUtf8(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(outcome, content="true")
}

///|
test "未收齐的 UTF-8 序列不能被引号或反斜杠吞掉" {
  // ["<E4>","x"]：E4 是三字节序列的首字节，却被闭合引号吞掉。
  // 必须在偏移 2 处立刻报 InvalidUtf8，而不是先交付一个空字符串。
  let bytes : Array[Byte] = [
    b'[', b'"', 0xE4, b'"', b',', b'"', b'x', b'"', b']',
  ]
  let err = expect_parse_error_bytes(Bytes::from_array(bytes))
  match err {
    @moonstream.ParseError::InvalidUtf8(pos~, ..) => inspect(pos, content="2")
    _ => fail("应当为 InvalidUtf8")
  }
  // "<E4>\n<80>"：反斜杠也不能吞掉待续字节
  let bytes2 : Array[Byte] = [b'"', 0xE4, b'\\', b'n', 0x80, b'"']
  let err2 = expect_parse_error_bytes(Bytes::from_array(bytes2))
  match err2 {
    @moonstream.ParseError::InvalidUtf8(pos~, ..) => inspect(pos, content="1")
    _ => fail("应当为 InvalidUtf8")
  }
  // 未收齐时遇到控制字符同样报错
  let bytes3 : Array[Byte] = [b'"', 0xE4, 0x01, b'"']
  let _ = expect_parse_error_bytes(Bytes::from_array(bytes3))
}
