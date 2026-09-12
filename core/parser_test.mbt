// 基本结构与事件序列。

///|
test "整段对象：事件序列、路径与完成结果" {
  let source = "{\"city\":\"上海\",\"count\":12,\"ok\":true,\"note\":null,\"items\":[1,2]}"
  let (events, result) = parse_whole(source)
  let doc = expect_completed(result)
  inspect(doc.to_string(), content=source)
  inspect(
    render_events(events),
    content=(
      #|{$@0-1 | key:city@1-7 | delta$.city=上海@8-15 | value$.city=上海@8-16 | key:count@17-24 | value$.count=12@25-27 | key:ok@28-32 | value$.ok=true@33-37 | key:note@38-44 | value$.note=null@45-49 | key:items@50-57 | [$.items@58-59 | value$.items[0]=1@59-60 | value$.items[1]=2@61-62 | ]$.items@62-63 | }$@63-64
    ),
  )
}

///|
test "根标量：数字保留原始词法" {
  let (events, result) = parse_whole("1.5e3")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="1.5e3")
  inspect(
    render_events(events),
    content=(
      #|value$=1.5e3@0-5
    ),
  )
}

///|
test "根标量：字符串增量先于完成事件" {
  let (events, result) = parse_whole("\"hi\"")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="\"hi\"")
  inspect(
    render_events(events),
    content=(
      #|delta$=hi@0-3 | value$=hi@0-4
    ),
  )
}

///|
test "空容器" {
  let (events, result) = parse_whole("{\"a\":{},\"b\":[]}")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"a\":{},\"b\":[]}")
  inspect(
    render_events(events),
    content=(
      #|{$@0-1 | key:a@1-4 | {$.a@5-6 | }$.a@6-7 | key:b@8-11 | [$.b@12-13 | ]$.b@13-14 | }$@14-15
    ),
  )
}

///|
test "嵌套路径渲染" {
  let path = @moonstream.Path::root()
    .child_key("items")
    .child_index(0)
    .child_key("name")
  inspect(path.to_string(), content="$.items[0].name")
  inspect(path.length(), content="3")
  inspect(path.is_root(), content="false")
  inspect(@moonstream.Path::root().is_root(), content="true")
}

///|
test "事件的路径与区间访问器" {
  let rendered = []
  // 两种文档合起来覆盖全部事件构造器
  for source in ["{\"a\":\"b\"}", "[10]"] {
    let (events, _) = parse_whole(source)
    for event in events {
      rendered.push(
        "\{event.path().to_string()}:\{event.span().start}-\{event.span().end}",
      )
    }
  }
  inspect(
    rendered.join(" "),
    content=(
      #|$:0-1 $.a:1-4 $.a:5-7 $.a:5-8 $:8-9 $:0-1 $[0]:1-3 $:3-4
    ),
  )
}

///|
test "Span 长度" {
  let span = @moonstream.Span::new(3, 7)
  inspect(span.length(), content="4")
  inspect(span.start, content="3")
  inspect(span.end, content="7")
}

///|
test "空白与换行不产生事件" {
  let (events, result) = parse_whole("  \n\t {\r\n \"a\" \t : \n 1 \n } \n ")
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="  \n\t {\r\n \"a\" \t : \n 1 \n } \n ")
  inspect(
    render_events(events),
    content=(
      #|{$@5-6 | key:a@9-12 | value$.a=1@19-20 | }$@23-24
    ),
  )
}

///|
test "空输入块不改变语义" {
  let parser = @moonstream.Parser::new()
  let first = parser.feed(b"")
  inspect(first.length(), content="0")
  let second = parser.feed(b"{\"a\":1}")
  inspect(second.length(), content="4")
  let third = parser.feed(b"")
  inspect(third.length(), content="0")
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"a\":1}")
}

///|
test "数字被分隔符确认完成：逗号前不能提前完成" {
  let parser = @moonstream.Parser::new()
  let events = parser.feed(b"{\"count\":1")
  inspect(
    render_events(events),
    content=(
      #|{$@0-1 | key:count@1-8
    ),
  )
  let more = parser.feed(b"2}")
  inspect(
    render_events(more),
    content=(
      #|value$.count=12@9-11 | }$@11-12
    ),
  )
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"count\":12}")
}
