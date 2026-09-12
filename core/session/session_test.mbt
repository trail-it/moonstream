// Session：多 tool call 路由、交错输入、冲突与错误包装。

///|
/// 构造一个带 response 标识的调用键。
fn call_key(index : Int) -> @session.CallKey {
  @session.CallKey::new(response="resp-1", choice=0, index~)
}

///|
test "两个调用的参数片段交错到达互不干扰" {
  let session = @session.Session::new()
  let first = call_key(0)
  let second = call_key(1)
  session.open(first, id=Some("call_a"), name=Some("create_ticket"))
  session.open(second, id=Some("call_b"), name=Some("send_mail"))
  // 交错喂入
  let _ = session.feed(first, b"{\"title\":\"登")
  let _ = session.feed(second, b"{\"to\":\"a@")
  let _ = session.feed(first, b"录失败\"}")
  let _ = session.feed(second, b"example.com\"}")
  let (_, first_result) = session.finish(first)
  let (_, second_result) = session.finish(second)
  match first_result {
    @moonstream.FinishResult::Completed(doc) =>
      inspect(doc.to_string(), content="{\"title\":\"登录失败\"}")
    _ => fail("第一个调用应当完成")
  }
  match second_result {
    @moonstream.FinishResult::Completed(doc) =>
      inspect(doc.to_string(), content="{\"to\":\"a@example.com\"}")
    _ => fail("第二个调用应当完成")
  }
  inspect(session.call_name(first) is Some(_), content="true")
  inspect(session.is_finished(first), content="true")
  inspect(session.is_finished(second), content="true")
  inspect(session.open_calls().length(), content="0")
}

///|
test "不同 choice 或不同 response 的相同 index 是不同调用" {
  let session = @session.Session::new()
  let a = @session.CallKey::new(response="resp-1", choice=0, index=0)
  let b = @session.CallKey::new(response="resp-1", choice=1, index=0)
  let c = @session.CallKey::new(response="resp-2", choice=0, index=0)
  session.open(a)
  session.open(b)
  session.open(c)
  let _ = session.feed(a, b"[1]")
  let _ = session.feed(b, b"[2]")
  let _ = session.feed(c, b"[3]")
  let (_, ra) = session.finish(a)
  let (_, rb) = session.finish(b)
  let (_, rc) = session.finish(c)
  inspect(document_of(ra), content="[1]")
  inspect(document_of(rb), content="[2]")
  inspect(document_of(rc), content="[3]")
}

///|
/// 取出完成文档文本。
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
test "没有起始上下文就喂入必须报错" {
  let session = @session.Session::new()
  let key = call_key(0)
  let outcome = try {
    let _ = session.feed(key, b"{}")
    "no error"
  } catch {
    @session.SessionError::UnknownCall(..) => "UnknownCall"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(outcome, content="UnknownCall")
  // finish 同样要求先注册
  let finish_outcome = try {
    let _ = session.finish(key)
    "no error"
  } catch {
    @session.SessionError::UnknownCall(..) => "UnknownCall"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(finish_outcome, content="UnknownCall")
}

///|
test "同一调用的 id 冲突必须报错" {
  let session = @session.Session::new()
  let key = call_key(0)
  session.open(key, id=Some("call_a"), name=Some("create_ticket"))
  // 重复注册相同元数据是幂等的
  session.open(key, id=Some("call_a"))
  session.open(key, name=Some("create_ticket"))
  let outcome = try {
    session.open(key, id=Some("call_b"))
    "no error"
  } catch {
    @session.SessionError::CallIdConflict(existing~, incoming~, ..) =>
      "\{existing}->\{incoming}"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(outcome, content="call_a->call_b")
  let name_outcome = try {
    session.open(key, name=Some("send_mail"))
    "no error"
  } catch {
    @session.SessionError::CallNameConflict(existing~, incoming~, ..) =>
      "\{existing}->\{incoming}"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(name_outcome, content="create_ticket->send_mail")
}

///|
test "一个调用失败不影响其它调用" {
  let session = @session.Session::new()
  let bad = call_key(0)
  let good = call_key(1)
  session.open(bad)
  session.open(good)
  let _ = session.feed(good, b"{\"ok\":")
  let failure = try {
    let _ = session.feed(bad, b"{oops}")
    "no error"
  } catch {
    @session.SessionError::ParseFailed(
      error=@moonstream.ParseError::InvalidSyntax(..),
      ..
    ) => "ParseFailed(InvalidSyntax)"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(failure, content="ParseFailed(InvalidSyntax)")
  inspect(session.is_open(bad), content="false")
  inspect(session.is_failed(bad), content="true")
  inspect(session.is_finished(bad), content="false")
  inspect(session.failure(bad) is Some(_), content="true")
  debug_inspect(
    session.open_calls(),
    content="[{ response: \"resp-1\", choice: 0, index: 1 }]",
  )
  // 另一个调用照常继续
  let _ = session.feed(good, b"true}")
  let (_, result) = session.finish(good)
  inspect(document_of(result), content="{\"ok\":true}")
}

///|
test "取消单个调用不影响其它调用" {
  let session = @session.Session::new()
  let cancelled = call_key(0)
  let normal = call_key(1)
  session.open(cancelled)
  session.open(normal)
  let _ = session.feed(cancelled, b"{\"a\":1}")
  let _ = session.feed(normal, b"[1,2]")
  let (_, cancelled_result) = session.finish(
    cancelled,
    reason=@moonstream.EndReason::Cancelled,
  )
  inspect(
    cancelled_result is @moonstream.FinishResult::Aborted(..),
    content="true",
  )
  let (_, normal_result) = session.finish(normal)
  inspect(document_of(normal_result), content="[1,2]")
}

///|
test "会话状态可观测" {
  let session = @session.Session::new()
  let key = call_key(3)
  inspect(session.is_open(key), content="false")
  inspect(session.call_count(), content="0")
  session.open(key, id=Some("call_x"), name=Some("do_thing"))
  inspect(session.is_open(key), content="true")
  inspect(session.is_finished(key), content="false")
  inspect(session.call_count(), content="1")
  inspect(session.open_calls().length(), content="1")
  debug_inspect(session.call_id(key), content="Some(\"call_x\")")
  debug_inspect(session.call_name(key), content="Some(\"do_thing\")")
  debug_inspect(session.offset(key), content="Some(0)")
  let _ = session.feed(key, b"{\"a\":")
  debug_inspect(session.offset(key), content="Some(5)")
  let _ = session.finish(key)
  inspect(session.is_open(key), content="false")
  inspect(session.is_finished(key), content="true")
  inspect(session.call_count(), content="1")
}

///|
test "已结束的调用再次 feed 或 finish 都报 ParseFailed" {
  let session = @session.Session::new()
  let key = call_key(0)
  session.open(key)
  let _ = session.feed(key, b"[1]")
  let (_, result) = session.finish(key)
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
  let feed_again = try {
    let _ = session.feed(key, b" ")
    "no error"
  } catch {
    @session.SessionError::ParseFailed(
      error=@moonstream.ParseError::AlreadyFinished(..),
      ..
    ) => "ParseFailed(AlreadyFinished)"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(feed_again, content="ParseFailed(AlreadyFinished)")
  let finish_again = try {
    let _ = session.finish(key)
    "no error"
  } catch {
    @session.SessionError::ParseFailed(
      error=@moonstream.ParseError::AlreadyFinished(..),
      ..
    ) => "ParseFailed(AlreadyFinished)"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(finish_again, content="ParseFailed(AlreadyFinished)")
  // 其它调用不受影响
  let other = call_key(1)
  session.open(other)
  let _ = session.feed(other, b"[2]")
  let (_, other_result) = session.finish(other)
  inspect(document_of(other_result), content="[2]")
}

///|
test "Session::new 用 SessionError 报告非法限制" {
  let bad : @moonstream.Limits = {
    max_depth: 0,
    max_token_bytes: 1,
    max_nodes: 1,
    max_total_bytes: 1,
  }
  let outcome = try {
    let _ = @session.Session::new(limits=bad)
    "no error"
  } catch {
    @session.SessionError::InvalidLimits(..) => "InvalidLimits"
    _ => "other"
  } noraise {
    _ => "no error"
  }
  inspect(outcome, content="InvalidLimits")
}
