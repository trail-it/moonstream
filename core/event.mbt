///|
/// 数字的原始词法形式。
///
/// 保留 `1e400`、`123456789012345678901234567890` 这类输入的原样文本，
/// 避免在解析阶段就把大整数或高精度小数静默舍入为 `Double`。
pub(all) struct NumberLiteral {
  lexeme : String
} derive(Eq, Debug, ToJson)

///|
pub fn NumberLiteral::new(lexeme : String) -> NumberLiteral {
  { lexeme, }
}

///|
/// 原始文本。
pub fn NumberLiteral::lexeme(self : NumberLiteral) -> String {
  self.lexeme
}

///|
/// 按 IEEE 754 双精度解析。这是**显式的有损转换**：
///
/// - 上溢（如 `1e309`）返回 `None`；
/// - 下溢（如 `1e-400`）按 IEEE 754 归零，返回 `Some(0.0)`；
/// - 词法不是数字时返回 `None`。
///
/// `NumberLiteral::new` 不校验词法，因此传入 `inf` / `nan` 这类文本时结果由底层
/// 解析器决定；解析器自己产出的字面量总是合法 JSON 数字。需要无损语义时请使用
/// `lexeme`。
pub fn NumberLiteral::to_double(self : NumberLiteral) -> Double? {
  try @str.parse_double(self.lexeme) catch {
    _ => None
  } noraise {
    d => Some(d)
  }
}

///|
/// 已完成叶值的取值。
pub(all) enum LeafValue {
  Null
  Bool(Bool)
  Number(NumberLiteral)
  String(String)
} derive(Eq, Debug, ToJson)

///|
/// 解析器在输入增量上产生的结构事件。
///
/// 事件是**增量观察**，不是最终结果：`ValueComplete` 只表示该叶值已被语法边界确认，
/// 整个文档是否合法仍由 `Parser::finish` 决定。
pub(all) enum Event {
  ObjectBegin(path~ : Path, span~ : Span)
  ObjectEnd(path~ : Path, span~ : Span)
  ArrayBegin(path~ : Path, span~ : Span)
  ArrayEnd(path~ : Path, span~ : Span)
  /// 一个对象键名已经完整读出（键的转义与 UTF-8 已解码）。
  KeyComplete(path~ : Path, name~ : String, span~ : Span)
  /// 值字符串的增量文本，可能被后续输入继续延长。
  StringDelta(path~ : Path, text~ : String, span~ : Span)
  /// 一个叶值（字符串 / 数字 / true / false / null）已被语法边界确认完成。
  ValueComplete(path~ : Path, value~ : LeafValue, span~ : Span)
} derive(Eq, Debug, ToJson)

///|
/// 事件所属路径。
pub fn Event::path(self : Event) -> Path {
  match self {
    ObjectBegin(path~, ..) => path
    ObjectEnd(path~, ..) => path
    ArrayBegin(path~, ..) => path
    ArrayEnd(path~, ..) => path
    KeyComplete(path~, ..) => path
    StringDelta(path~, ..) => path
    ValueComplete(path~, ..) => path
  }
}

///|
/// 事件对应的字节区间。
pub fn Event::span(self : Event) -> Span {
  match self {
    ObjectBegin(span~, ..) => span
    ObjectEnd(span~, ..) => span
    ArrayBegin(span~, ..) => span
    ArrayEnd(span~, ..) => span
    KeyComplete(span~, ..) => span
    StringDelta(span~, ..) => span
    ValueComplete(span~, ..) => span
  }
}
