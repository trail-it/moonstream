// 部分树节点：Preview 的内部表示。

///|
/// 一个预览节点的种类。
priv enum NodeKind {
  /// 对象：已完成成员按插入顺序保存在 map 中。
  NObj(Map[String, Node])
  /// 数组：元素按顺序保存。
  NArr(Array[Node])
  /// 正在增长的字符串值。
  NStr(StringBuilder)
  /// 已完成的叶值。
  NLeaf(@moonstream.LeafValue)
  /// 键已知，但值还不可用（例如数字正在扫描）。
  NPending
}

///|
/// 预览树节点。结构体是引用类型，因此子节点可以原地更新。
priv struct Node {
  mut closed : Bool
  mut kind : NodeKind
}

///|
fn Node::object() -> Node {
  { closed: false, kind: NObj(Map([])) }
}

///|
fn Node::array() -> Node {
  { closed: false, kind: NArr([]) }
}

///|
fn Node::string() -> Node {
  { closed: false, kind: NStr(StringBuilder::new()) }
}

///|
fn Node::leaf(value : @moonstream.LeafValue) -> Node {
  { closed: true, kind: NLeaf(value) }
}

///|
fn Node::pending() -> Node {
  { closed: false, kind: NPending }
}
