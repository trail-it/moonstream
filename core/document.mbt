///|
/// 已经过完整合法性检查的 JSON 文档。
///
/// 本类型没有公开构造器，构造权属于解析器。它只代表“该文档在 MoonStream
/// 的严格语法策略下完整且合法”，**不**代表模型意图正确、符合业务 Schema、
/// 获得执行授权，或可以安全地产生副作用。
pub struct CompletedDocument {
  text : String
  /// 文档的原始字节数（不是 UTF-16 码元数）。
  byte_length : Int
} derive(Eq, ToJson, Debug)

///|
/// 私有构造器：只有同包的解析器可以创建。
fn CompletedDocument::new(
  text : String,
  byte_length : Int,
) -> CompletedDocument {
  { text, byte_length }
}

///|
/// 原始完整文本。
pub fn CompletedDocument::to_string(self : CompletedDocument) -> String {
  self.text
}

///|
/// 文档的原始字节数。
///
/// 这是解析器实际消费的字节数，对非 ASCII 文档与 `to_string().length()`
/// （UTF-16 码元数）不同。
pub fn CompletedDocument::byte_length(self : CompletedDocument) -> Int {
  self.byte_length
}

///|
/// 转换为 `Json`。
///
/// 这是显式操作：`Json` 的数值语义会做双精度转换，需要无损数字时请使用
/// 事件流里的 `NumberLiteral`。转换失败时抛出 JSON 解析错误。
pub fn CompletedDocument::to_json(
  self : CompletedDocument,
) -> Json raise @json.ParseError {
  @json.parse(self.text)
}

///|
/// `finish` 的结束原因。
///
/// 只有 `EndOfStream` 可能产生 `CompletedDocument`：取消或截断都不代表
/// 模型已经说完，即使此刻文本看起来恰好完整。
pub(all) enum EndReason {
  EndOfStream
  Cancelled
  Truncated
} derive(Eq, Debug, ToJson)

///|
/// `finish` 的结果。
pub(all) enum FinishResult {
  /// 文档完整且合法。
  Completed(CompletedDocument)
  /// 输入合法但尚未结束；`pos` 是缺失内容的位置，`expected` 是期待的内容。
  Incomplete(pos~ : Int, expected~ : String)
  /// 结束原因不是正常结束，不产生结果对象。
  Aborted(reason~ : EndReason)
} derive(Eq, ToJson, Debug)
