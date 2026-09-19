// Preview：把事件流投影成部分树，供 UI 逐帧渲染。
//
// Preview 是**只读投影**：它没有、也不会有把部分树变成 `CompletedDocument`
// 的公开构造器。已经显示出来的预览不等于整个参数合法。

///|
/// 容器种类。
pub(all) enum ContainerKind {
  Object
  Array
} derive(Eq, Debug, ToJson)

///|
/// 某个路径在预览树中的状态。
///
/// 四个"没有值"的情况被显式区分：路径不存在、值还不可用、字符串未完成、
/// 以及真正完成的 JSON `null`。
pub(all) enum NodeState {
  /// 该路径不存在。
  Missing
  /// 键已知但值还不可用（刚读完冒号，或数字/字面量正在扫描）。只出现在对象成员上。
  Pending
  /// 容器；`closed` 表示闭合括号是否已经出现。
  Container(kind~ : ContainerKind, closed~ : Bool)
  /// 字符串值正在增长。
  IncompleteString(text~ : String)
  /// 已完成的叶值（`LeafValue::Null` 就是 JSON null）。
  Complete(value~ : @moonstream.LeafValue)
} derive(Eq, Debug, ToJson)

///|
/// 投影过程中的错误。事件必须来自同一个文档且顺序合法。
pub(all) suberror PreviewError {
  /// 事件与已有树结构冲突（例如把字符串增量送到容器节点）。
  PathConflict(path~ : @moonstream.Path, detail~ : String)
  /// 事件的父路径不存在。
  MissingParent(path~ : @moonstream.Path)
} derive(Eq, Debug, ToJson)

///|
/// 部分树投影。
pub struct Preview {
  inner : PreviewState
}

///|
/// 预览树的全部状态。私有实现细节，不是可用 API。
struct PreviewState {
  /// `None` 表示还没有任何节点（根路径也是 `Missing`）。
  mut root : Node?
  mut count : Int
}

///|
/// 空预览。
pub fn Preview::new() -> Preview {
  { inner: { root: None, count: 0, }, }
}

///|
/// 是否还没有任何节点。
pub fn Preview::is_empty(self : Preview) -> Bool {
  self.inner.root is None
}

///|
/// 已保留的节点数量（含容器、字符串与叶值）。
pub fn Preview::node_count(self : Preview) -> Int {
  self.inner.count
}

///|
/// 丢弃全部节点，用于调用方控制保留量。
pub fn Preview::clear(self : Preview) -> Unit {
  self.inner.root = None
  self.inner.count = 0
}

///|
/// 消费一个事件并更新部分树。
///
/// 事件必须按解析器产出顺序送入；顺序错误或结构冲突会抛出 `PreviewError`。
pub fn Preview::apply(
  self : Preview,
  event : @moonstream.Event,
) -> Unit raise PreviewError {
  match event {
    @moonstream.Event::ObjectBegin(path~, ..) =>
      self.replace(path, Node::object())
    @moonstream.Event::ArrayBegin(path~, ..) =>
      self.replace(path, Node::array())
    @moonstream.Event::ObjectEnd(path~, ..)
    | @moonstream.Event::ArrayEnd(path~, ..) =>
      match self.find(path) {
        Some(node) => node.closed = true
        None => raise PreviewError::MissingParent(path~)
      }
    @moonstream.Event::KeyComplete(path~, ..) => {
      let _ = self.ensure(path, Node::pending())
    }
    @moonstream.Event::StringDelta(path~, text~, ..) => {
      let node = self.ensure(path, Node::string())
      match node.kind {
        NStr(buffer) => {
          buffer.write_string(text)
          node.closed = false
        }
        NPending => {
          let buffer = StringBuilder()
          buffer.write_string(text)
          node.kind = NStr(buffer)
          node.closed = false
        }
        _ =>
          raise PreviewError::PathConflict(
            path~,
            detail="字符串增量到达了非字符串节点",
          )
      }
    }
    @moonstream.Event::ValueComplete(path~, value~, ..) =>
      self.replace(path, Node::leaf(value))
  }
}

///|
/// 按顺序消费一批解析事件。
///
/// 等价于逐个调用 `apply`；如果中途出现冲突，错误之前的事件已经生效。
pub fn Preview::apply_all(
  self : Preview,
  events : ArrayView[@moonstream.Event],
) -> Unit raise PreviewError {
  for event in events {
    self.apply(event)
  }
}

///|
/// 查询路径的当前状态。
pub fn Preview::lookup(self : Preview, path : @moonstream.Path) -> NodeState {
  match self.find(path) {
    None => NodeState::Missing
    Some(node) => node_state(node)
  }
}

///|
/// 枚举一个容器的直接子节点，按插入顺序返回 `(片段, 状态)`。
///
/// 路径不存在或不是容器时返回空数组。UI 用它渲染"键名还不知道"的对象。
pub fn Preview::children(
  self : Preview,
  path : @moonstream.Path,
) -> Array[(@moonstream.PathSegment, NodeState)] {
  let out = []
  match self.find(path) {
    None => ()
    Some(node) =>
      match node.kind {
        NObj(entries) =>
          for key, child in entries {
            out.push((@moonstream.PathSegment::Key(key), node_state(child)))
          }
        NArr(items) =>
          for index, child in items {
            out.push((@moonstream.PathSegment::Index(index), node_state(child)))
          }
        _ => ()
      }
  }
  out
}

///|
/// 返回当前预览里已经完成的全部叶值，按对象插入顺序和数组下标顺序遍历。
///
/// `Pending`、未闭合字符串和容器自身不会出现在结果中。这里的“完成”只表示
/// 对应叶值不会再变化，不代表整篇文档已经可以交付。
pub fn Preview::completed_leaves(
  self : Preview,
) -> Array[(@moonstream.Path, @moonstream.LeafValue)] {
  let out = []
  match self.inner.root {
    Some(root) => collect_completed(root, @moonstream.Path::root(), out)
    None => ()
  }
  out
}

///|
fn collect_completed(
  node : Node,
  path : @moonstream.Path,
  out : Array[(@moonstream.Path, @moonstream.LeafValue)],
) -> Unit {
  match node.kind {
    NObj(entries) =>
      for key, child in entries {
        collect_completed(child, path.child_key(key), out)
      }
    NArr(items) =>
      for index, child in items {
        collect_completed(child, path.child_index(index), out)
      }
    NLeaf(value) => out.push((path, value))
    NPending | NStr(_) => ()
  }
}

///|
/// 单个节点的状态。
fn node_state(node : Node) -> NodeState {
  match node.kind {
    NPending => NodeState::Pending
    NObj(_) => NodeState::Container(kind=Object, closed=node.closed)
    NArr(_) => NodeState::Container(kind=Array, closed=node.closed)
    NStr(buffer) => NodeState::IncompleteString(text=buffer.to_string())
    NLeaf(value) => NodeState::Complete(value~)
  }
}

///|
/// 渲染成带"未完成"标记的类 JSON 文本，用于调试与 UI 预览。
///
/// **这不是合法 JSON**：未闭合的字符串以 `…` 结尾，还没有值的键渲染为 `…`。
pub fn Preview::to_preview_string(self : Preview) -> String {
  match self.inner.root {
    None => "<empty>"
    Some(root) => render_node(root)
  }
}

///|
/// 按路径查找节点。空路径在还没有任何节点时返回 `None`。
fn Preview::find(self : Preview, path : @moonstream.Path) -> Node? {
  let root = match self.inner.root {
    Some(root) => root
    None => return None
  }
  if path.segments.is_empty() {
    return Some(root)
  }
  let mut cursor = root
  for segment in path.segments {
    let next = match (cursor.kind, segment) {
      (NObj(entries), @moonstream.PathSegment::Key(key)) => entries.get(key)
      (NArr(items), @moonstream.PathSegment::Index(index)) => items.get(index)
      _ => None
    }
    match next {
      Some(node) => cursor = node
      None => return None
    }
  }
  Some(cursor)
}

///|
/// 在路径处放置节点；父路径不存在时报错。
fn Preview::replace(
  self : Preview,
  path : @moonstream.Path,
  node : Node,
) -> Unit raise PreviewError {
  match self.find(path) {
    Some(current) => {
      current.kind = node.kind
      current.closed = node.closed
    }
    None => self.insert(path, node)
  }
}

///|
/// 取路径处的节点；不存在则创建。
fn Preview::ensure(
  self : Preview,
  path : @moonstream.Path,
  node : Node,
) -> Node raise PreviewError {
  match self.find(path) {
    Some(current) => current
    None => {
      self.insert(path, node)
      node
    }
  }
}

///|
/// 在路径处插入新节点。
fn Preview::insert(
  self : Preview,
  path : @moonstream.Path,
  node : Node,
) -> Unit raise PreviewError {
  let segments = path.segments
  if segments.is_empty() {
    self.inner.root = Some(node)
    self.inner.count = self.inner.count + 1
    return
  }
  let root = match self.inner.root {
    Some(root) => root
    None => raise PreviewError::MissingParent(path~)
  }
  let mut cursor = root
  let last_index = segments.length() - 1
  for i in 0..<last_index {
    let next = match (cursor.kind, segments[i]) {
      (NObj(entries), @moonstream.PathSegment::Key(key)) => entries.get(key)
      (NArr(items), @moonstream.PathSegment::Index(index)) => items.get(index)
      _ => None
    }
    match next {
      Some(child) => cursor = child
      None => raise PreviewError::MissingParent(path~)
    }
  }
  let last = segments[segments.length() - 1]
  match (cursor.kind, last) {
    (NObj(entries), @moonstream.PathSegment::Key(key)) => entries[key] = node
    (NArr(items), @moonstream.PathSegment::Index(index)) =>
      if index < items.length() {
        items[index] = node
      } else if index == items.length() {
        items.push(node)
      } else {
        raise PreviewError::MissingParent(path~)
      }
    _ =>
      raise PreviewError::PathConflict(
        path~,
        detail="路径与容器类型不匹配",
      )
  }
  self.inner.count = self.inner.count + 1
}

///|
/// 递归渲染节点。
fn render_node(node : Node) -> String {
  match node.kind {
    NPending => "…"
    NLeaf(value) => render_leaf(value)
    NStr(buffer) =>
      if node.closed {
        "\"" + buffer.to_string() + "\""
      } else {
        "\"" + buffer.to_string() + "…"
      }
    NObj(entries) => {
      let parts = []
      for key, child in entries {
        parts.push("\"" + key + "\":" + render_node(child))
      }
      "{" + parts.join(",") + (if node.closed { "}" } else { ",…}" })
    }
    NArr(items) => {
      let parts = []
      for item in items {
        parts.push(render_node(item))
      }
      "[" + parts.join(",") + (if node.closed { "]" } else { ",…]" })
    }
  }
}

///|
/// 叶值的类 JSON 文本。
fn render_leaf(value : @moonstream.LeafValue) -> String {
  match value {
    @moonstream.LeafValue::Null => "null"
    @moonstream.LeafValue::Bool(b) => b.to_string()
    @moonstream.LeafValue::Number(n) => n.lexeme()
    @moonstream.LeafValue::String(s) => "\"" + s + "\""
  }
}
