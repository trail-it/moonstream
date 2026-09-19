// Preview 的部分树投影：状态区分、增量字符串、渲染与保留量控制。

///|
/// 把一段输入喂给解析器，并把事件全部投影到预览树。
fn project(
  parser : @moonstream.Parser,
  preview : @preview.Preview,
  bytes : Bytes,
) -> Unit raise {
  for event in parser.feed(bytes) {
    preview.apply(event)
  }
}

///|
/// 构造对象成员路径。
fn key_path(name : String) -> @moonstream.Path {
  @moonstream.Path::root().child_key(name)
}

///|
fn leaf_text(value : @moonstream.LeafValue) -> String {
  match value {
    @moonstream.LeafValue::Null => "null"
    @moonstream.LeafValue::Bool(value) => value.to_string()
    @moonstream.LeafValue::Number(value) => value.lexeme()
    @moonstream.LeafValue::String(value) => value
  }
}

///|
test "四种状态互不混淆" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  project(parser, preview, b"{\"city\":\"上")
  // 字符串正在增长
  json_inspect(preview.lookup(key_path("city")), content=[
    "IncompleteString",
    { "text": "上" },
  ])
  // 根是未闭合的对象
  json_inspect(preview.lookup(@moonstream.Path::root()), content=[
    "Container",
    { "kind": "Object", "closed": false },
  ])
  // 不存在的路径
  json_inspect(preview.lookup(key_path("missing")), content="Missing")
  project(parser, preview, b"海\",\"count\":12,\"note\":null}")
  json_inspect(preview.lookup(key_path("city")), content=[
    "Complete",
    { "value": ["String", "上海"] },
  ])
  json_inspect(preview.lookup(key_path("count")), content=[
    "Complete",
    { "value": ["Number", { "lexeme": "12" }] },
  ])
  // 完成的 JSON null 与 Missing 必须区分
  json_inspect(preview.lookup(key_path("note")), content=[
    "Complete",
    { "value": "Null" },
  ])
  json_inspect(preview.lookup(key_path("other")), content="Missing")
  json_inspect(preview.lookup(@moonstream.Path::root()), content=[
    "Container",
    { "kind": "Object", "closed": true },
  ])
}

///|
test "批量投影只枚举已经完成的叶值" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  preview.apply_all(
    parser.feed_text(
      "{\"done\":1,\"nested\":{\"ok\":true},\"pending\":\"正在",
    ),
  )
  let leaves = preview.completed_leaves()
  inspect(leaves.length(), content="2")
  inspect(leaves[0].0.to_string(), content="$.done")
  inspect(leaf_text(leaves[0].1), content="1")
  inspect(leaves[1].0.to_string(), content="$.nested.ok")
  inspect(leaf_text(leaves[1].1), content="true")
  inspect(
    preview.lookup(key_path("pending"))
    is @preview.NodeState::IncompleteString(_),
    content="true",
  )
}

///|
test "键已知但值还不可用时是 Pending" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  project(parser, preview, b"{\"count\":")
  json_inspect(preview.lookup(key_path("count")), content="Pending")
  project(parser, preview, b"1")
  // 数字还没被分隔符确认
  json_inspect(preview.lookup(key_path("count")), content="Pending")
  project(parser, preview, b",\"next\":")
  json_inspect(preview.lookup(key_path("count")), content=[
    "Complete",
    { "value": ["Number", { "lexeme": "1" }] },
  ])
  json_inspect(preview.lookup(key_path("next")), content="Pending")
}

///|
test "数组元素路径与闭合状态" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  project(parser, preview, b"{\"items\":[1,{\"k\":\"v\"}")
  let items = key_path("items")
  json_inspect(preview.lookup(items), content=[
    "Container",
    { "kind": "Array", "closed": false },
  ])
  json_inspect(preview.lookup(items.child_index(0)), content=[
    "Complete",
    { "value": ["Number", { "lexeme": "1" }] },
  ])
  json_inspect(preview.lookup(items.child_index(1)), content=[
    "Container",
    { "kind": "Object", "closed": true },
  ])
  json_inspect(preview.lookup(items.child_index(1).child_key("k")), content=[
    "Complete",
    { "value": ["String", "v"] },
  ])
  project(parser, preview, b"]}")
  json_inspect(preview.lookup(items), content=[
    "Container",
    { "kind": "Array", "closed": true },
  ])
  json_inspect(preview.lookup(items.child_index(1)), content=[
    "Container",
    { "kind": "Object", "closed": true },
  ])
}

///|
test "逐帧渲染未完成内容" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  inspect(preview.to_preview_string(), content="<empty>")
  project(parser, preview, b"{\"city\":\"上")
  inspect(preview.to_preview_string(), content="{\"city\":\"上…,…}")
  project(parser, preview, b"海\",\"count\":")
  inspect(
    preview.to_preview_string(),
    content="{\"city\":\"上海\",\"count\":…,…}",
  )
  project(parser, preview, b"12}")
  inspect(
    preview.to_preview_string(),
    content="{\"city\":\"上海\",\"count\":12}",
  )
}

///|
test "节点数与清空" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  inspect(preview.is_empty(), content="true")
  // 空预览的根路径是 Missing，而不是一个占位容器
  json_inspect(preview.lookup(@moonstream.Path::root()), content="Missing")
  project(parser, preview, b"{\"a\":1,\"b\":2}")
  inspect(preview.is_empty(), content="false")
  // 根 + a + b
  inspect(preview.node_count(), content="3")
  preview.clear()
  inspect(preview.node_count(), content="0")
  inspect(preview.is_empty(), content="true")
  json_inspect(preview.lookup(key_path("a")), content="Missing")
  json_inspect(preview.lookup(@moonstream.Path::root()), content="Missing")
}

///|
test "children 枚举容器的直接子节点" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  project(parser, preview, b"{\"a\":1,\"b\":\"x\",\"c\":[true]}")
  let root_children = preview.children(@moonstream.Path::root())
  inspect(root_children.length(), content="3")
  inspect(
    render_children(root_children),
    content="Key(a)=1,Key(b)=x,Key(c)=<array>",
  )
  let array_children = preview.children(key_path("c"))
  inspect(render_children(array_children), content="Index(0)=true")
  // 非容器与不存在的路径都返回空
  inspect(preview.children(key_path("a")).length(), content="0")
  inspect(preview.children(key_path("missing")).length(), content="0")
  inspect(
    preview.children(@moonstream.Path::root().child_index(9)).length(),
    content="0",
  )
}

///|
/// 把子节点列表渲染成便于断言的文本。
fn render_children(
  children : Array[(@moonstream.PathSegment, @preview.NodeState)],
) -> String {
  let parts = []
  for entry in children {
    let (segment, state) = entry
    let name = match segment {
      @moonstream.PathSegment::Key(key) => "Key(\{key})"
      @moonstream.PathSegment::Index(index) => "Index(\{index})"
    }
    let value = match state {
      @preview.NodeState::Missing => "<missing>"
      @preview.NodeState::Pending => "<pending>"
      @preview.NodeState::Container(kind=@preview.ContainerKind::Object, ..) =>
        "<object>"
      @preview.NodeState::Container(kind=@preview.ContainerKind::Array, ..) =>
        "<array>"
      @preview.NodeState::IncompleteString(text~) => text
      @preview.NodeState::Complete(value=@moonstream.LeafValue::String(s)) => s
      @preview.NodeState::Complete(value=@moonstream.LeafValue::Number(n)) =>
        n.lexeme()
      @preview.NodeState::Complete(value=@moonstream.LeafValue::Bool(b)) =>
        b.to_string()
      @preview.NodeState::Complete(value=@moonstream.LeafValue::Null) => "null"
    }
    parts.push("\{name}=\{value}")
  }
  parts.join(",")
}

///|
test "根值是字符串：可以投影，不再被占位节点挡住" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  project(parser, preview, b"\"hi\"")
  json_inspect(preview.lookup(@moonstream.Path::root()), content=[
    "Complete",
    { "value": ["String", "hi"] },
  ])
  inspect(preview.node_count(), content="1")
  inspect(preview.to_preview_string(), content="\"hi\"")
}

///|
test "根值是标量：lookup、计数与渲染一致" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  // 数字要等分隔符或 finish 才完成，因此这里必须把收尾事件也投影进去
  project(parser, preview, b"42")
  let (tail, result) = parser.finish()
  for event in tail {
    preview.apply(event)
  }
  inspect(result is @moonstream.FinishResult::Completed(_), content="true")
  json_inspect(preview.lookup(@moonstream.Path::root()), content=[
    "Complete",
    { "value": ["Number", { "lexeme": "42" }] },
  ])
  inspect(preview.node_count(), content="1")
  inspect(preview.is_empty(), content="false")
  inspect(preview.to_preview_string(), content="42")
}

///|
test "finish 的收尾事件也能投影（未完成文档）" {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  project(parser, preview, b"[1,2")
  let (tail, result) = parser.finish()
  for event in tail {
    preview.apply(event)
  }
  inspect(result is @moonstream.FinishResult::Incomplete(..), content="true")
  json_inspect(preview.lookup(@moonstream.Path::root().child_index(1)), content=[
    "Complete",
    { "value": ["Number", { "lexeme": "2" }] },
  ])
  inspect(preview.to_preview_string(), content="[1,2,…]")
}

///|
test "结构冲突必须报错" {
  let preview = @preview.Preview::new()
  let root = @moonstream.Path::root()
  preview.apply(
    @moonstream.Event::ObjectBegin(path=root, span=@moonstream.Span::new(0, 1)),
  )
  let conflict = try {
    preview.apply(
      @moonstream.Event::StringDelta(
        path=root,
        text="x",
        span=@moonstream.Span::new(1, 2),
      ),
    )
    false
  } catch {
    @preview.PreviewError::PathConflict(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(conflict, content="true")
}

///|
test "预览与最终文档一致，但预览不能当作结果" {
  let source = "{\"tool\":\"create_ticket\",\"args\":{\"title\":\"登录失败\",\"priority\":3}}"
  let bytes = @utf8.encode(source)
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  let mut mid_snapshot = ""
  for i in 0..<bytes.length() {
    project(parser, preview, Bytes::from_array(bytes[i:i + 1].to_array()))
    if i == bytes.length() - 5 {
      mid_snapshot = preview.to_preview_string()
    }
  }
  // 中途的预览带有未完成标记，不是可用的结果
  inspect(
    mid_snapshot.has_prefix("{\"tool\":\"create_ticket\""),
    content="true",
  )
  inspect(mid_snapshot.contains("…"), content="true")
  // 全部完成后，渲染结果与原始文本一致
  inspect(preview.to_preview_string(), content=source)
  let (_, result) = parser.finish()
  match result {
    @moonstream.FinishResult::Completed(doc) =>
      inspect(doc.to_string(), content=source)
    _ => fail("应当完成")
  }
}
