// 负面控制：这些输入无论如何继续都必须失败，不能只靠“全绿样例”证明校验有效。

///|
/// 断言整段解析（含 finish）会抛出错误。
fn expect_parse_error(source : String) -> @moonstream.ParseError raise {
  expect_parse_error_bytes(utf8_bytes(source))
}

///|
/// 字节级版本，用于构造非法 UTF-8。
fn expect_parse_error_bytes(bytes : Bytes) -> @moonstream.ParseError raise {
  let parser = @moonstream.Parser::new()
  let outcome = try {
    let _ = parser.feed(bytes)
    let _ = parser.finish()
    ()
  } catch {
    err => Some(err)
  } noraise {
    _ => None
  }
  match outcome {
    Some(err) => err
    None => fail("期待解析失败")
  }
}

///|
/// 断言错误属于指定的构造器。
fn assert_error_kind(source : String, expected : String) -> Unit raise {
  let err = expect_parse_error(source)
  let actual = match err {
    @moonstream.ParseError::InvalidSyntax(..) => "InvalidSyntax"
    @moonstream.ParseError::InvalidUtf8(..) => "InvalidUtf8"
    @moonstream.ParseError::InvalidEscape(..) => "InvalidEscape"
    @moonstream.ParseError::InvalidNumber(..) => "InvalidNumber"
    @moonstream.ParseError::InvalidUnicodeEscape(..) => "InvalidUnicodeEscape"
    @moonstream.ParseError::DuplicateKey(..) => "DuplicateKey"
    @moonstream.ParseError::TrailingContent(..) => "TrailingContent"
    @moonstream.ParseError::LimitExceeded(..) => "LimitExceeded"
    @moonstream.ParseError::AlreadyFinished(..) => "AlreadyFinished"
    @moonstream.ParseError::InvalidLimits(..) => "InvalidLimits"
  }
  inspect(actual, content=expected)
}

///|
test "结构错误必须失败" {
  let cases = [
    "{\"a\":1,}", "[1,]", "{\"a\" 1}", "{a:1}", "[1 2]", "[1,,2]", "{\"a\":\"b\"c}",
    "[}", "{]", "{\"a\"}", "{,}", "{\"a\":}", "{\"a\":1 \"b\":2}",
  ]
  for source in cases {
    let _ = expect_parse_error(source)
  }
}

///|
test "根值之后的非空白内容必须失败" {
  for
    source in [
      "{\"a\":1}}", "{\"a\":1} x", "\"a\"\"b\"", "12 34", "truex", "nullx",
    ] {
    assert_error_kind(source, "TrailingContent")
  }
}

///|
test "非法数字必须失败" {
  let cases = [
    "01", "{\"a\":01}", "{\"a\":1.}", "{\"a\":1e}", "{\"a\":1e+}", "{\"a\":-}", "{\"a\":1..2}",
    "{\"a\":00}", "{\"a\":1.2.3}", "{\"a\":1e1e1}", "{\"a\":1.2e}",
  ]
  for source in cases {
    assert_error_kind(source, "InvalidNumber")
  }
  // 值起始位置就不是数字：属于语法错误而不是数字词法错误
  assert_error_kind("{\"a\":.5}", "InvalidSyntax")
  assert_error_kind("{\"a\":+1}", "InvalidSyntax")
  // 数字本身合法（`123`），后面跟的 `abc` 是容器层面的语法错误
  assert_error_kind("{\"a\":123abc}", "InvalidSyntax")
}

///|
test "字面量必须逐字匹配" {
  // `nul` 后面不是 `l`
  assert_error_kind("nulx", "InvalidSyntax")
  // 字面量内部出现空白
  assert_error_kind("tru e", "InvalidSyntax")
  assert_error_kind("truex", "TrailingContent")
  // 值起始位置出现不可打印字节
  let err = expect_parse_error_bytes([0x01])
  match err {
    @moonstream.ParseError::InvalidSyntax(..) => inspect("ok", content="ok")
    _ => fail("应当为 InvalidSyntax")
  }
}

///|
test "非法转义与代理项必须失败" {
  assert_error_kind("{\"a\":\"\\x\"}", "InvalidEscape")
  assert_error_kind("{\"a\":\"\\u12\"}", "InvalidUnicodeEscape")
  assert_error_kind("{\"a\":\"\\uZZZZ\"}", "InvalidUnicodeEscape")
  assert_error_kind("{\"a\":\"\\uD800\"}", "InvalidUnicodeEscape")
  assert_error_kind("{\"a\":\"\\uDC00\"}", "InvalidUnicodeEscape")
  assert_error_kind("{\"a\":\"\\uD800\\u0041\"}", "InvalidUnicodeEscape")
  assert_error_kind("{\"a\":\"\\uD800x\"}", "InvalidUnicodeEscape")
}

///|
test "重复键必须失败" {
  assert_error_kind("{\"a\":1,\"a\":2}", "DuplicateKey")
  assert_error_kind("{\"a\":{\"b\":1,\"b\":2}}", "DuplicateKey")
}

///|
test "非法 UTF-8 必须失败" {
  // 孤立的续字节
  assert_error_kind_bytes(
    [b'{', b'"', b'a', b'"', b':', b'"', 0x80, b'"', b'}'],
    "InvalidUtf8",
  )
  // 0xC0 属于过度长编码的起始字节
  assert_error_kind_bytes([b'"', 0xC0, 0xAF, b'"'], "InvalidUtf8")
  // 代理项 ED A0 80
  assert_error_kind_bytes([b'"', 0xED, 0xA0, 0x80, b'"'], "InvalidUtf8")
  // 超过 U+10FFFF：F4 90 80 80
  assert_error_kind_bytes([b'"', 0xF4, 0x90, 0x80, 0x80, b'"'], "InvalidUtf8")
  // 续字节数量不足
  assert_error_kind_bytes([b'"', 0xE4, 0xB8, b'"'], "InvalidUtf8")
}

///|
/// 字节级断言错误构造器。
fn assert_error_kind_bytes(
  bytes : Array[Byte],
  expected : String,
) -> Unit raise {
  let err = expect_parse_error_bytes(Bytes::from_array(bytes))
  let actual = match err {
    @moonstream.ParseError::InvalidUtf8(..) => "InvalidUtf8"
    _ => "other"
  }
  inspect(actual, content=expected)
}

///|
test "错误后解析器进入终止状态" {
  let parser = @moonstream.Parser::new()
  let failed = try {
    let _ = parser.feed(b"{a")
    false
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  inspect(failed, content="true")
  // 错误之后再次 feed / finish 都必须抛 AlreadyFinished，而不是继续解析
  let feed_again = try {
    let _ = parser.feed(b"}")
    false
  } catch {
    @moonstream.ParseError::AlreadyFinished(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(feed_again, content="true")
  let finish_again = try {
    let _ = parser.finish()
    false
  } catch {
    @moonstream.ParseError::AlreadyFinished(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(finish_again, content="true")
}

///|
test "重复 finish 与 finish 后 feed 行为固定" {
  let parser = @moonstream.Parser::new()
  let _ = parser.feed(b"1")
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="1")
  let second = try {
    let _ = parser.finish()
    false
  } catch {
    @moonstream.ParseError::AlreadyFinished(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(second, content="true")
  let feed_after = try {
    let _ = parser.feed(b" ")
    false
  } catch {
    @moonstream.ParseError::AlreadyFinished(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(feed_after, content="true")
}
