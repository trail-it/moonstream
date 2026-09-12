///|
test "CallUpdate 保留调用键与事件归属" {
  let key = @session.CallKey::new(response="r", choice=1, index=2)
  let update = @adapter.CallUpdate::delta(key, [])
  inspect(update.key == key, content="true")
  inspect(update.events.length(), content="0")
  inspect(update.result is None, content="true")
  match @adapter.AdapterOutcome::Updates(updates=[update]).updates() {
    [actual] => inspect(actual.key == key, content="true")
    _ => fail("应返回一条带键更新")
  }
}

///|
test "批量收尾保留早先结果并越过在 finish 才失败的调用" {
  let session = @session.Session::new()
  for index in 0..<3 {
    session.open(@session.CallKey::new(index~))
  }
  let _ = session.feed(@session.CallKey::new(index=0), b"1")
  let _ = session.feed(@session.CallKey::new(index=1), b"\"\xe4")
  let _ = session.feed(@session.CallKey::new(index=2), b"2")
  let updates = @adapter.finish_open(
    session,
    @moonstream.EndReason::EndOfStream,
  )
  assert_eq(updates.length(), 3)
  for index in [0, 2] {
    assert_eq(updates[index].key.index, index)
    assert_true(
      updates[index].result is Some(@moonstream.FinishResult::Completed(_)),
    )
    assert_eq(updates[index].events.length(), 1)
    assert_true(updates[index].failure is None)
  }
  assert_true(updates[1].result is None)
  assert_true(
    updates[1].failure is Some(@session.SessionError::ParseFailed(..)),
  )
  assert_true(session.is_failed(@session.CallKey::new(index=1)))
  assert_eq(session.open_calls().length(), 0)
}

///|
test "结束更新显式携带不可交付结果" {
  let key = @session.CallKey::new(index=0)
  let update = @adapter.CallUpdate::finished(
    key,
    [],
    @moonstream.FinishResult::Aborted(reason=@moonstream.EndReason::Truncated),
  )
  inspect(
    update.result is Some(@moonstream.FinishResult::Aborted(..)),
    content="true",
  )
}
