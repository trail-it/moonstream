///|
/// 资源限制的类型。
pub(all) enum LimitKind {
  Depth
  TokenBytes
  Nodes
  TotalBytes
} derive(Eq, Debug, ToJson)

///|
/// UTF-8 解码失败的类别。
pub(all) enum Utf8ErrorKind {
  /// 首字节不在合法范围内（0x80..0xC1、0xF5..0xFF）。
  InvalidLeadByte
  /// 续字节不是 0x80..0xBF。
  InvalidContinuation
  /// 过度长编码，例如用两字节编码 ASCII。
  OverlongEncoding
  /// 编码了 UTF-16 代理项码位（U+D800..U+DFFF）。
  SurrogateCodePoint
  /// 码点超过 U+10FFFF。
  OutOfRange
} derive(Eq, Debug, ToJson)

///|
/// 解析器可以抛出的错误。
///
/// 任何一次抛出都使解析器进入终止状态：不会“尽力恢复”后继续产出事件。
pub(all) suberror ParseError {
  /// 语法不符合 JSON 文法。
  InvalidSyntax(pos~ : Int, expected~ : String, found~ : String)
  /// 输入不是合法 UTF-8。
  InvalidUtf8(pos~ : Int, kind~ : Utf8ErrorKind)
  /// 字符串里出现非法转义或未转义控制字符。
  InvalidEscape(pos~ : Int, detail~ : String)
  /// 数字词法非法。
  InvalidNumber(pos~ : Int, lexeme~ : String)
  /// `\u` 转义非法，或出现孤立代理项。
  InvalidUnicodeEscape(pos~ : Int, detail~ : String)
  /// 同一对象内出现重复键（V1 严格拒绝）。
  DuplicateKey(pos~ : Int, key~ : String, path~ : Path)
  /// 根值之后又出现非空白内容。
  TrailingContent(pos~ : Int)
  /// 触发资源限制。
  LimitExceeded(kind~ : LimitKind, pos~ : Int, allowed~ : Int, actual~ : Int)
  /// 调用顺序错误（例如 finish 之后再次 feed）。
  AlreadyFinished(op~ : String)
  /// 限制参数本身不合法。
  InvalidLimits(detail~ : String)
} derive(Eq, Debug, ToJson)
