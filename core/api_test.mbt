// 公开 API 的收敛测试：长度口径、状态查询、相等性与列表接口。

///|
test "byte_length 是原始字节数，不是 UTF-16 码元数" {
  // 每个汉字 3 字节、1 个 UTF-16 码元
  let source = "{\"city\":\"上海\"}"
  let (_, result) = parse_whole(source)
  let doc = expect_completed(result)
  inspect(doc.byte_length(), content="17")
  inspect(doc.to_string().length(), content="13")
  // ASCII 文档两者一致
  let (_, ascii) = parse_whole("{\"a\":1}")
  let ascii_doc = expect_completed(ascii)
  inspect(ascii_doc.byte_length(), content="7")
  inspect(ascii_doc.to_string().length(), content="7")
}

///|
test "Parser::is_finished 反映终止状态" {
  let parser = @moonstream.Parser::new()
  inspect(parser.is_finished(), content="false")
  let _ = parser.feed(b"[1]")
  inspect(parser.is_finished(), content="false")
  let (_, result) = parser.finish()
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
  inspect(parser.is_finished(), content="true")
}

///|
test "解析错误后 Parser::is_finished 也为真" {
  let parser = @moonstream.Parser::new()
  let failed = try {
    let _ = parser.feed(b"{oops}")
    false
  } catch {
    _ => true
  } noraise {
    _ => false
  }
  inspect(failed, content="true")
  inspect(parser.is_finished(), content="true")
}

///|
test "FinishResult 可以比较相等" {
  let (_, first) = parse_whole("[1,2]")
  let (_, second) = parse_whole("[1,2]")
  let (_, different) = parse_whole("[1,3]")
  inspect(first == second, content="true")
  inspect(first == different, content="false")
}

///|
test "Session::calls 返回全部已注册调用" {
  let session = @session.Session::new()
  let first = @session.CallKey::new(response="r", choice=0, index=0)
  let second = @session.CallKey::new(response="r", choice=0, index=1)
  session.open(first)
  session.open(second, id=Some("call_b"))
  let _ = session.feed(first, b"[]")
  let _ = session.finish(first)
  // open_calls 只给未结束的；calls 给全部
  inspect(session.open_calls().length(), content="1")
  inspect(session.calls().length(), content="2")
  inspect(session.call_count(), content="2")
  inspect(session.calls()[0] == first, content="true")
  inspect(session.calls()[1] == second, content="true")
}

///|
test "Session::open 的标签参数可以只给一个" {
  let session = @session.Session::new()
  let key = @session.CallKey::new(response="r", choice=0, index=0)
  session.open(key, name=Some("only_name"))
  debug_inspect(session.call_id(key), content="None")
  debug_inspect(session.call_name(key), content="Some(\"only_name\")")
}
