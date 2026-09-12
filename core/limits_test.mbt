// 资源限制与生命周期。

///|
/// 断言给定限制下解析会抛出 LimitExceeded，并返回具体种类。
fn expect_limit(
  limits : @moonstream.Limits,
  bytes : Bytes,
) -> @moonstream.LimitKind raise {
  let parser = @moonstream.Parser::new(limits~)
  let outcome = try {
    let _ = parser.feed(bytes)
    ()
  } catch {
    err => Some(err)
  } noraise {
    _ => None
  }
  match outcome {
    Some(@moonstream.ParseError::LimitExceeded(kind~, ..)) => kind
    Some(_) => fail("期待 LimitExceeded")
    None => fail("期待 LimitExceeded，但没有失败")
  }
}

///|
test "深度限制" {
  let limits = @moonstream.Limits::new(max_depth=3)
  inspect(
    expect_limit(limits, b"[[[[1]]]]") is @moonstream.LimitKind::Depth,
    content="true",
  )
  // 三层正好在上限内，不应触发限制
  let parser = @moonstream.Parser::new(limits~)
  let _ = parser.feed(b"[[[1]]]")
  let (_, result) = parser.finish()
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
}

///|
test "节点数限制" {
  let limits = @moonstream.Limits::new(max_nodes=3)
  inspect(
    expect_limit(limits, b"[1,2,3]") is @moonstream.LimitKind::Nodes,
    content="true",
  )
  // 数组加两个元素共 3 个节点，正好在上限内
  let parser = @moonstream.Parser::new(limits~)
  let _ = parser.feed(b"[1,2]")
  let (_, result) = parser.finish()
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
}

///|
test "单 token 字节限制" {
  let limits = @moonstream.Limits::new(max_token_bytes=4)
  inspect(
    expect_limit(limits, b"{\"a\":\"123\"}")
    is @moonstream.LimitKind::TokenBytes,
    content="true",
  )
  // `"12"` 连同引号正好 4 字节，不触发限制
  let parser = @moonstream.Parser::new(limits~)
  let _ = parser.feed(b"{\"a\":\"12\"}")
  let (_, result) = parser.finish()
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
}

///|
test "总输入限制" {
  let limits = @moonstream.Limits::new(max_total_bytes=3)
  inspect(
    expect_limit(limits, b"{\"a\":1}") is @moonstream.LimitKind::TotalBytes,
    content="true",
  )
}

///|
test "跨多个块累加总输入限制" {
  let limits = @moonstream.Limits::new(max_total_bytes=4)
  let parser = @moonstream.Parser::new(limits~)
  let _ = parser.feed(b"[1,")
  let outcome = try {
    let _ = parser.feed(b"2]")
    false
  } catch {
    @moonstream.ParseError::LimitExceeded(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(outcome, content="true")
}

///|
test "总输入超限诊断不依赖分块方式" {
  let limits = @moonstream.Limits::new(max_total_bytes=3)
  let whole = @moonstream.Parser::new(limits~)
  let whole_error : @moonstream.ParseError? = try {
    let _ = whole.feed(b"true")
    (None : @moonstream.ParseError?)
  } catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  let split = @moonstream.Parser::new(limits~)
  let _ = split.feed(b"tru")
  let split_error : @moonstream.ParseError? = try {
    let _ = split.feed(b"e")
    (None : @moonstream.ParseError?)
  } catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  inspect(whole_error == split_error, content="true")
  match whole_error {
    Some(@moonstream.ParseError::LimitExceeded(pos~, actual~, ..)) => {
      inspect(pos, content="3")
      inspect(actual, content="4")
    }
    _ => fail("应报告第一个超限字节")
  }
}

///|
test "总输入预检不会遮蔽更早的语法错误" {
  let parser = @moonstream.Parser::new(
    limits=@moonstream.Limits::new(max_total_bytes=3),
  )
  let result = try {
    let _ = parser.feed(b"!xxx")
    "no error"
  } catch {
    @moonstream.ParseError::InvalidSyntax(pos~, ..) => "syntax@\{pos}"
    _ => "other error"
  } noraise {
    _ => "no error"
  }
  inspect(result, content="syntax@0")
}

///|
/// 断言某个非法上限被拒绝。
fn invalid_limit_rejected(which : String) -> Bool {
  try {
    let _ = match which {
      "depth" => @moonstream.Limits::new(max_depth=0)
      "token" => @moonstream.Limits::new(max_token_bytes=0)
      "nodes" => @moonstream.Limits::new(max_nodes=0)
      _ => @moonstream.Limits::new(max_total_bytes=0)
    }
    false
  } catch {
    @moonstream.ParseError::InvalidLimits(..) => true
    _ => false
  } noraise {
    _ => false
  }
}

///|
test "非法限制被拒绝" {
  // 四个上限都必须为正数
  for which in ["depth", "token", "nodes", "total"] {
    inspect(invalid_limit_rejected(which), content="true")
  }
}

///|
test "直接构造的非法 Limits 会被 Parser::new 拒绝" {
  let limits : @moonstream.Limits = {
    max_depth: 1,
    max_token_bytes: 1,
    max_nodes: 1,
    max_total_bytes: -1,
  }
  let rejected = try {
    let _ = @moonstream.Parser::new(limits~)
    false
  } catch {
    @moonstream.ParseError::InvalidLimits(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}

///|
test "取消与截断不产生结果对象" {
  for
    reason in [
      @moonstream.EndReason::Cancelled,
      @moonstream.EndReason::Truncated,
    ] {
    let parser = @moonstream.Parser::new()
    let _ = parser.feed(b"{\"a\":1}")
    let (_, result) = parser.finish(reason~)
    match result {
      @moonstream.FinishResult::Aborted(reason=got) =>
        inspect(got == reason, content="true")
      _ => fail("取消/截断不应产生 CompletedDocument")
    }
  }
}

///|
test "取消时即使文本完整也不成功" {
  let parser = @moonstream.Parser::new()
  let _ = parser.feed(b"123")
  let (_, result) = parser.finish(reason=@moonstream.EndReason::Cancelled)
  inspect(result is @moonstream.FinishResult::Aborted(..), content="true")
}

///|
test "解析器状态可观测" {
  let parser = @moonstream.Parser::new()
  inspect(parser.offset(), content="0")
  let _ = parser.feed(b"{\"a\":")
  inspect(parser.offset(), content="5")
  let _ = parser.feed(utf8_bytes("\"上"))
  inspect(parser.offset(), content="9")
  let limits = parser.limits()
  inspect(limits.max_depth, content="128")
  inspect(limits.max_total_bytes, content="67108864")
}
