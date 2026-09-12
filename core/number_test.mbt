// 数字：词法保留、完成时机、显式有损转换。

///|
/// 取第一个完成事件的数字字面量。
fn first_number(
  events : Array[@moonstream.Event],
) -> @moonstream.NumberLiteral raise {
  for event in events {
    match event {
      @moonstream.Event::ValueComplete(
        value=@moonstream.LeafValue::Number(n),
        ..
      ) => return n
      _ => ()
    }
  }
  fail("没有找到数字完成事件")
}

///|
test "合法数字形式" {
  let cases = [
    "0", "1", "-0", "-1", "123", "1.5", "-1.5", "1e3", "1E3", "1e+3", "1e-3", "0.5",
    "1.5e3", "-0.001", "1e10", "123456789012345678901234567890", "0e1", "0E1", "-0e-1",
    "0.0e+0",
  ]
  for source in cases {
    let (events, result) = parse_whole(source)
    let doc = expect_completed(result)
    inspect(doc.to_string(), content=source)
    let literal = first_number(events)
    inspect(literal.lexeme(), content=source)
  }
}

///|
test "数字只有在被分隔符确认后才完成" {
  let parser = @moonstream.Parser::new()
  let first = parser.feed(b"{\"count\":1")
  inspect(
    render_events(first),
    content=(
      #|{$@0-1 | key:count@1-8
    ),
  )
  let second = parser.feed(b"2")
  inspect(render_events(second), content="")
  let third = parser.feed(b".5")
  inspect(render_events(third), content="")
  let fourth = parser.feed(b"e2")
  inspect(render_events(fourth), content="")
  let fifth = parser.feed(b",\"done\":true}")
  inspect(
    render_events(fifth),
    content=(
      #|value$.count=12.5e2@9-15 | key:done@16-22 | value$.done=true@23-27 | }$@27-28
    ),
  )
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"count\":12.5e2,\"done\":true}")
}

///|
test "数字被逗号确认完成，但根仍处于接收状态" {
  let parser = @moonstream.Parser::new()
  let events = parser.feed(b"{\"count\":1,")
  inspect(
    render_events(events),
    content=(
      #|{$@0-1 | key:count@1-8 | value$.count=1@9-10
    ),
  )
  let (_, result) = parser.finish()
  match result {
    @moonstream.FinishResult::Incomplete(expected~, ..) =>
      inspect(expected, content="对象键")
    _ => fail("应当为 Incomplete")
  }
}

///|
test "未完成的数字前缀在 finish 时是 Incomplete" {
  for source in ["1e", "1e+", "1.", "-", "0."] {
    let (_, result) = parse_whole(source)
    match result {
      @moonstream.FinishResult::Incomplete(..) =>
        inspect("incomplete", content="incomplete")
      _ => fail("\{source} 应当为 Incomplete")
    }
  }
}

///|
test "大整数保留词法，to_double 是显式有损转换" {
  let source = "123456789012345678901234567890"
  let (events, result) = parse_whole(source)
  let _ = expect_completed(result)
  let literal = first_number(events)
  inspect(literal.lexeme(), content=source)
  match literal.to_double() {
    Some(d) => inspect(d > 1.0e29, content="true")
    None => fail("应当可以转换为 Double")
  }
  inspect(
    @moonstream.NumberLiteral::new("1.5").to_double() is Some(_),
    content="true",
  )
  inspect(
    @moonstream.NumberLiteral::new("abc").to_double() is None,
    content="true",
  )
}

///|
test "超出双精度范围的数字：词法保留，转换结果被明确记录" {
  let literal = @moonstream.NumberLiteral::new("1e309")
  inspect(literal.lexeme(), content="1e309")
  // 解析本身不拒绝它：词法合法。转换到 Double 才可能溢出。
  let (_, result) = parse_whole("1e309")
  inspect(expect_completed(result).to_string(), content="1e309")
  match literal.to_double() {
    Some(value) => inspect(value.is_inf(), content="true")
    None => inspect("none", content="none")
  }
}

///|
test "to_double 的溢出与下溢行为" {
  // 上溢：词法保留，但转成 Double 失败（返回 None）
  let (_, result) = parse_whole("1e309")
  inspect(expect_completed(result).to_string(), content="1e309")
  inspect(
    @moonstream.NumberLiteral::new("1e309").to_double() is None,
    content="true",
  )
  // 下溢：按 IEEE 754 归零（不是 None）
  match @moonstream.NumberLiteral::new("1e-400").to_double() {
    Some(value) => inspect(value == 0.0, content="true")
    None => fail("下溢应当得到 Some(0.0)")
  }
  // 词法不是数字
  inspect(
    @moonstream.NumberLiteral::new("abc").to_double() is None,
    content="true",
  )
  inspect(
    @moonstream.NumberLiteral::new("").to_double() is None,
    content="true",
  )
}

///|
test "CompletedDocument::to_json 的数字表示" {
  // Json 使用最短往返表示，因此 `1e3` 会规范化成 `1000`；
  // 需要原始词法时使用事件流里的 NumberLiteral。
  let source = "{\"big\":123456789012345678901234567890,\"f\":0.1}"
  let (_, result) = parse_whole(source)
  let doc = expect_completed(result)
  inspect(doc.to_json().stringify(), content=source)
  inspect(doc.byte_length(), content=source.length().to_string())
  let (_, exponent) = parse_whole("1e3")
  let exponent_doc = expect_completed(exponent)
  inspect(exponent_doc.to_json().stringify(), content="1000")
}

///|
test "指数数字跨块切分不变" {
  let source = "[-1.25e-10,0.0e+0,123456789012345678901234567890]"
  let bytes = utf8_bytes(source)
  for split in all_two_way_splits(bytes) {
    let (_, result) = parse_chunks(split)
    let doc = expect_completed(result)
    inspect(doc.to_string(), content=source)
  }
}
