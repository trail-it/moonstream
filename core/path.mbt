///|
/// JSON 文档内的路径片段。
pub(all) enum PathSegment {
  /// 对象成员，携带键名。
  Key(String)
  /// 数组元素，携带下标。
  Index(Int)
} derive(Eq, Debug, ToJson)

///|
/// 文档内某个值的位置。根路径为空。
///
/// 路径只描述结构位置，不携带任何“该值已经合法”的承诺。
pub(all) struct Path {
  segments : Array[PathSegment]
} derive(Eq, Debug, ToJson)

///|
/// 根路径（空路径）。
pub fn Path::root() -> Path {
  { segments: [] }
}

///|
/// 追加一个对象键片段。
pub fn Path::child_key(self : Path, key : String) -> Path {
  let segments = self.segments.copy()
  segments.push(PathSegment::Key(key))
  { segments, }
}

///|
/// 追加一个数组下标片段。
pub fn Path::child_index(self : Path, index : Int) -> Path {
  let segments = self.segments.copy()
  segments.push(PathSegment::Index(index))
  { segments, }
}

///|
/// 路径深度。
pub fn Path::length(self : Path) -> Int {
  self.segments.length()
}

///|
/// 是否为空路径（文档根）。
pub fn Path::is_root(self : Path) -> Bool {
  self.segments.is_empty()
}

///|
/// 渲染为 `$`、`$.city`、`$.items[0].name` 形式，便于日志与测试断言。
pub fn Path::to_string(self : Path) -> String {
  let out = StringBuilder()
  out.write_string("$")
  for segment in self.segments {
    match segment {
      PathSegment::Key(key) => {
        out.write_string(".")
        out.write_string(key)
      }
      PathSegment::Index(index) => {
        out.write_string("[")
        out.write_string(index.to_string())
        out.write_string("]")
      }
    }
  }
  out.to_string()
}
