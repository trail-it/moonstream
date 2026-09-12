///|
/// 输入中的绝对字节区间，`start` 含、`end` 不含。
///
/// 偏移以“本次解析会话收到的全部字节”为基准，与 chunk 切分方式无关。
pub(all) struct Span {
  start : Int
  end : Int
} derive(Eq, Debug, ToJson)

///|
pub fn Span::new(start : Int, end : Int) -> Span {
  { start, end }
}

///|
/// 区间长度（字节数）。
pub fn Span::length(self : Span) -> Int {
  self.end - self.start
}
