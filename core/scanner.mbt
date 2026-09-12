///|
/// 结构化扫描：空白与结构字符。
fn Parser::step_normal(
  self : Parser,
  b : Int,
  pos : Int,
) -> Unit raise ParseError {
  if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
    return
  }
  match self.inner.ctx {
    RootStart => self.start_value(b, pos)
    RootDone => raise ParseError::TrailingContent(pos~)
    ObjKeyOrEnd =>
      if b == 0x7D {
        self.close_container(pos)
      } else if b == 0x22 {
        self.begin_string(pos, true)
      } else {
        raise ParseError::InvalidSyntax(
          pos~,
          expected="对象键或 '}'",
          found=describe_byte(b),
        )
      }
    ObjKey =>
      if b == 0x22 {
        self.begin_string(pos, true)
      } else {
        raise ParseError::InvalidSyntax(
          pos~,
          expected="对象键",
          found=describe_byte(b),
        )
      }
    ObjColon =>
      if b == 0x3A {
        self.inner.ctx = ObjValue
      } else {
        raise ParseError::InvalidSyntax(
          pos~,
          expected="':'",
          found=describe_byte(b),
        )
      }
    ObjValue => self.start_value(b, pos)
    ObjCommaOrEnd =>
      if b == 0x2C {
        self.inner.ctx = ObjKey
      } else if b == 0x7D {
        self.close_container(pos)
      } else {
        raise ParseError::InvalidSyntax(
          pos~,
          expected="',' 或 '}'",
          found=describe_byte(b),
        )
      }
    ArrValueOrEnd =>
      if b == 0x5D {
        self.close_container(pos)
      } else {
        self.start_value(b, pos)
      }
    ArrValue => self.start_value(b, pos)
    ArrCommaOrEnd =>
      if b == 0x2C {
        self.inner.ctx = ArrValue
      } else if b == 0x5D {
        self.close_container(pos)
      } else {
        raise ParseError::InvalidSyntax(
          pos~,
          expected="',' 或 ']'",
          found=describe_byte(b),
        )
      }
  }
}

///|
/// 开始读取一个值。
fn Parser::start_value(
  self : Parser,
  b : Int,
  pos : Int,
) -> Unit raise ParseError {
  self.inner.cur_path = self.value_path()
  self.inner.node_count += 1
  if self.inner.node_count > self.inner.limits.max_nodes {
    raise ParseError::LimitExceeded(
      kind=LimitKind::Nodes,
      pos~,
      allowed=self.inner.limits.max_nodes,
      actual=self.inner.node_count,
    )
  }
  if b == 0x22 {
    self.begin_string(pos, false)
  } else if b == 0x7B {
    self.begin_container(FrameKind::Obj, pos)
  } else if b == 0x5B {
    self.begin_container(FrameKind::Arr, pos)
  } else if b == 0x2D || (b >= 0x30 && b <= 0x39) {
    self.begin_number(b, pos)
  } else if b == 0x74 {
    self.begin_literal(LitKind::LitTrue, 1, pos)
  } else if b == 0x66 {
    self.begin_literal(LitKind::LitFalse, 1, pos)
  } else if b == 0x6E {
    self.begin_literal(LitKind::LitNull, 1, pos)
  } else {
    raise ParseError::InvalidSyntax(
      pos~,
      expected="值",
      found=describe_byte(b),
    )
  }
}

///|
/// 打开一个容器。
fn Parser::begin_container(
  self : Parser,
  kind : FrameKind,
  pos : Int,
) -> Unit raise ParseError {
  let path = self.inner.cur_path
  let span = Span::new(pos, pos + 1)
  match kind {
    Obj => self.inner.events.push(Event::ObjectBegin(path~, span~))
    Arr => self.inner.events.push(Event::ArrayBegin(path~, span~))
  }
  self.inner.frames.push({
    kind,
    count: 0,
    keys: Map([]),
    path,
    pending_path: Path::root(),
  })
  if self.inner.frames.length() > self.inner.limits.max_depth {
    raise ParseError::LimitExceeded(
      kind=LimitKind::Depth,
      pos~,
      allowed=self.inner.limits.max_depth,
      actual=self.inner.frames.length(),
    )
  }
  self.inner.ctx = match kind {
    Obj => ObjKeyOrEnd
    Arr => ArrValueOrEnd
  }
}

///|
/// 关闭当前容器。
fn Parser::close_container(self : Parser, pos : Int) -> Unit raise ParseError {
  match self.inner.frames.pop() {
    None =>
      raise ParseError::InvalidSyntax(
        pos~,
        expected="容器",
        found=describe_byte(0x7D),
      )
    Some(frame) => {
      let span = Span::new(pos, pos + 1)
      match frame.kind {
        Obj => self.inner.events.push(Event::ObjectEnd(path=frame.path, span~))
        Arr => self.inner.events.push(Event::ArrayEnd(path=frame.path, span~))
      }
      self.after_child()
    }
  }
}

///|
/// 开始读取一个字符串（键或值）。
fn Parser::begin_string(self : Parser, pos : Int, in_key : Bool) -> Unit {
  self.inner.token_start = pos
  self.inner.token_bytes = 1
  self.inner.in_key = in_key
  self.inner.str_buf.reset()
  self.inner.str_delta.reset()
  self.inner.utf8_pending.clear()
  self.inner.utf8_expected = 0
  self.inner.utf8_start = -1
  self.inner.lex = LexStr
}

///|
/// 字符串内部扫描。
fn Parser::step_str(self : Parser, b : Int, pos : Int) -> Unit raise ParseError {
  self.bump_token(pos)
  // 已经收了一半的多字节序列，必须先把续字节补齐；`"`、`\` 与控制字符都不能
  // 把它吞掉，否则会向消费者交付一个并不存在的值，并把错误推迟到 finish。
  if self.inner.utf8_expected > 0 && (b < 0x80 || b > 0xBF) {
    let start = self.inner.utf8_start
    self.inner.utf8_pending.clear()
    self.inner.utf8_expected = 0
    self.inner.utf8_start = -1
    raise ParseError::InvalidUtf8(
      pos=start,
      kind=Utf8ErrorKind::InvalidContinuation,
    )
  }
  if b == 0x22 {
    self.close_string(pos)
    return
  }
  if b == 0x5C {
    self.inner.lex = LexStrEscape
    return
  }
  if b < 0x20 {
    raise ParseError::InvalidEscape(
      pos~,
      detail="字符串中出现未转义的控制字符",
    )
  }
  if b < 0x80 {
    match b.to_char() {
      Some(c) => self.push_char(c)
      None =>
        raise ParseError::InvalidEscape(
          pos~,
          detail="无法解码的 ASCII 字节",
        )
    }
    return
  }
  self.push_utf8_byte(b, pos)
}

///|
/// 转义序列的第一个字符。
fn Parser::step_escape(
  self : Parser,
  b : Int,
  pos : Int,
) -> Unit raise ParseError {
  self.bump_token(pos)
  match b {
    0x22 => {
      self.push_char('"')
      self.inner.lex = LexStr
    }
    0x5C => {
      self.push_char('\\')
      self.inner.lex = LexStr
    }
    0x2F => {
      self.push_char('/')
      self.inner.lex = LexStr
    }
    0x62 => {
      self.push_char('\u{8}')
      self.inner.lex = LexStr
    }
    0x66 => {
      self.push_char('\u{c}')
      self.inner.lex = LexStr
    }
    0x6E => {
      self.push_char('\n')
      self.inner.lex = LexStr
    }
    0x72 => {
      self.push_char('\r')
      self.inner.lex = LexStr
    }
    0x74 => {
      self.push_char('\t')
      self.inner.lex = LexStr
    }
    0x75 => self.inner.lex = LexStrHex(0, 0)
    _ => raise ParseError::InvalidEscape(pos~, detail="未知的转义序列")
  }
}

///|
/// `\uXXXX` 的四位十六进制。
fn Parser::step_hex(
  self : Parser,
  b : Int,
  pos : Int,
  count : Int,
  acc : Int,
) -> Unit raise ParseError {
  self.bump_token(pos)
  match hex_digit(b) {
    None =>
      raise ParseError::InvalidUnicodeEscape(
        pos~,
        detail="\\u 之后需要 4 位十六进制数字",
      )
    Some(value) => {
      let acc = acc * 16 + value
      if count + 1 == 4 {
        self.emit_escaped_code_point(acc, pos)
      } else {
        self.inner.lex = LexStrHex(count + 1, acc)
      }
    }
  }
}

///|
/// 高位代理之后必须紧跟 `\`。
fn Parser::step_low_slash(
  self : Parser,
  b : Int,
  pos : Int,
  hi : Int,
) -> Unit raise ParseError {
  self.bump_token(pos)
  if b == 0x5C {
    self.inner.lex = LexStrLowU(hi)
  } else {
    raise ParseError::InvalidUnicodeEscape(
      pos~,
      detail="高位代理后必须紧跟 \\u 低位代理",
    )
  }
}

///|
/// 高位代理之后必须紧跟 `u`。
fn Parser::step_low_u(
  self : Parser,
  b : Int,
  pos : Int,
  hi : Int,
) -> Unit raise ParseError {
  self.bump_token(pos)
  if b == 0x75 {
    self.inner.lex = LexStrLowHex(0, hi, 0)
  } else {
    raise ParseError::InvalidUnicodeEscape(
      pos~,
      detail="高位代理后必须紧跟 \\u 低位代理",
    )
  }
}

///|
/// 低位代理的四位十六进制。
fn Parser::step_low_hex(
  self : Parser,
  b : Int,
  pos : Int,
  count : Int,
  hi : Int,
  acc : Int,
) -> Unit raise ParseError {
  self.bump_token(pos)
  match hex_digit(b) {
    None =>
      raise ParseError::InvalidUnicodeEscape(
        pos~,
        detail="\\u 之后需要 4 位十六进制数字",
      )
    Some(value) => {
      let acc = acc * 16 + value
      if count + 1 < 4 {
        self.inner.lex = LexStrLowHex(count + 1, hi, acc)
      } else if acc >= 0xDC00 && acc <= 0xDFFF {
        let code_point = 0x10000 + ((hi - 0xD800) << 10) + (acc - 0xDC00)
        self.emit_escaped_code_point(code_point, pos)
      } else {
        raise ParseError::InvalidUnicodeEscape(
          pos~,
          detail="低位代理必须在 U+DC00..U+DFFF",
        )
      }
    }
  }
}

///|
/// 交付一个 `\u` 转义得到的码点；高位代理需要继续等待低位。
fn Parser::emit_escaped_code_point(
  self : Parser,
  code_point : Int,
  pos : Int,
) -> Unit raise ParseError {
  if code_point >= 0xD800 && code_point <= 0xDBFF {
    self.inner.lex = LexStrLowSlash(code_point)
    return
  }
  if code_point >= 0xDC00 && code_point <= 0xDFFF {
    raise ParseError::InvalidUnicodeEscape(pos~, detail="孤立的低位代理")
  }
  match code_point.to_char() {
    Some(c) => {
      self.push_char(c)
      self.inner.lex = LexStr
    }
    None =>
      raise ParseError::InvalidUnicodeEscape(
        pos~,
        detail="码点超出 Unicode 标量范围",
      )
  }
}

///|
/// 字符串结束：键走 `KeyComplete`，值走 `ValueComplete`。
fn Parser::close_string(self : Parser, pos : Int) -> Unit raise ParseError {
  let text = self.inner.str_buf.to_string()
  let span = Span::new(self.inner.token_start, pos + 1)
  if self.inner.in_key {
    match self.inner.frames.last() {
      None =>
        raise ParseError::InvalidSyntax(pos~, expected="对象键", found="键")
      Some(frame) => {
        if frame.keys.contains(text) {
          raise ParseError::DuplicateKey(pos~, key=text, path=frame.path)
        }
        frame.keys[text] = ()
        let path = frame.path.child_key(text)
        frame.pending_path = path
        self.inner.events.push(Event::KeyComplete(path~, name=text, span~))
        self.inner.ctx = ObjColon
      }
    }
  } else {
    // 先交付剩余增量：保证「同一字符串的所有增量合并后恰好覆盖完整文本」
    // 在任意分块方式下都成立。
    //
    // 增量区间用 `pos`（不含闭合引号），与 feed 末尾 flush 用的 `offset`
    // 口径一致——否则分块边界落在闭合引号上时区间会差 1 字节。
    if !self.inner.str_delta.is_empty() {
      self.inner.events.push(
        Event::StringDelta(
          path=self.inner.cur_path,
          text=self.inner.str_delta.to_string(),
          span=Span::new(self.inner.token_start, pos),
        ),
      )
      self.inner.str_delta.reset()
    }
    self.inner.events.push(
      Event::ValueComplete(
        path=self.inner.cur_path,
        value=LeafValue::String(text),
        span~,
      ),
    )
    self.after_child()
  }
  self.inner.str_delta.reset()
  self.inner.lex = LexNormal
}

///|
/// 把已解码的字符写入缓冲区。
fn Parser::push_char(self : Parser, c : Char) -> Unit {
  self.inner.str_buf.write_char(c)
  if !self.inner.in_key {
    self.inner.str_delta.write_char(c)
  }
}

///|
/// 字符串内部的 UTF-8 多字节序列。
fn Parser::push_utf8_byte(
  self : Parser,
  b : Int,
  pos : Int,
) -> Unit raise ParseError {
  if self.inner.utf8_expected == 0 {
    let want = if b >= 0xC2 && b <= 0xDF {
      2
    } else if b >= 0xE0 && b <= 0xEF {
      3
    } else if b >= 0xF0 && b <= 0xF4 {
      4
    } else {
      0
    }
    if want == 0 {
      raise ParseError::InvalidUtf8(pos~, kind=Utf8ErrorKind::InvalidLeadByte)
    }
    self.inner.utf8_pending.push(b)
    self.inner.utf8_expected = want
    self.inner.utf8_start = pos
    return
  }
  if b < 0x80 || b > 0xBF {
    let start = self.inner.utf8_start
    self.inner.utf8_pending.clear()
    self.inner.utf8_expected = 0
    self.inner.utf8_start = -1
    raise ParseError::InvalidUtf8(
      pos=start,
      kind=Utf8ErrorKind::InvalidContinuation,
    )
  }
  self.inner.utf8_pending.push(b)
  if self.inner.utf8_pending.length() < self.inner.utf8_expected {
    return
  }
  let width = self.inner.utf8_expected
  let start = self.inner.utf8_start
  let b0 = self.inner.utf8_pending[0]
  let b1 = self.inner.utf8_pending[1]
  let b2 = if width > 2 { self.inner.utf8_pending[2] } else { 0 }
  let b3 = if width > 3 { self.inner.utf8_pending[3] } else { 0 }
  self.inner.utf8_pending.clear()
  self.inner.utf8_expected = 0
  self.inner.utf8_start = -1
  let code_point = if width == 2 {
    ((b0 & 0x1F) << 6) | (b1 & 0x3F)
  } else if width == 3 {
    ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
  } else {
    ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
  }
  if width == 3 && code_point < 0x800 {
    raise ParseError::InvalidUtf8(
      pos=start,
      kind=Utf8ErrorKind::OverlongEncoding,
    )
  }
  if width == 3 && code_point >= 0xD800 && code_point <= 0xDFFF {
    raise ParseError::InvalidUtf8(
      pos=start,
      kind=Utf8ErrorKind::SurrogateCodePoint,
    )
  }
  if width == 4 && code_point < 0x10000 {
    raise ParseError::InvalidUtf8(
      pos=start,
      kind=Utf8ErrorKind::OverlongEncoding,
    )
  }
  if width == 4 && code_point > 0x10FFFF {
    raise ParseError::InvalidUtf8(pos=start, kind=Utf8ErrorKind::OutOfRange)
  }
  match code_point.to_char() {
    Some(c) => self.push_char(c)
    None =>
      raise ParseError::InvalidUtf8(pos=start, kind=Utf8ErrorKind::OutOfRange)
  }
}

///|
/// 开始读取一个数字。
fn Parser::begin_number(self : Parser, b : Int, pos : Int) -> Unit {
  self.inner.token_start = pos
  self.inner.token_bytes = 1
  self.inner.num_buf.reset()
  self.inner.num_buf.write_char(ascii_char(b))
  self.inner.num_state = if b == 0x2D {
    NumSign
  } else if b == 0x30 {
    NumZero
  } else {
    NumInt
  }
  self.inner.lex = LexNum
}

///|
/// 数字内部扫描。返回 `false` 表示当前字节不属于该数字，需要重新按结构字符处理。
fn Parser::step_num(self : Parser, b : Int, pos : Int) -> Bool raise ParseError {
  let digit = b >= 0x30 && b <= 0x39
  let next : NumState? = match self.inner.num_state {
    NumSign =>
      if digit {
        Some(if b == 0x30 { NumZero } else { NumInt })
      } else {
        None
      }
    NumZero =>
      if b == 0x2E {
        Some(NumDot)
      } else if b == 0x65 || b == 0x45 {
        Some(NumExp)
      } else {
        None
      }
    NumInt =>
      if digit {
        Some(NumInt)
      } else if b == 0x2E {
        Some(NumDot)
      } else if b == 0x65 || b == 0x45 {
        Some(NumExp)
      } else {
        None
      }
    NumDot => if digit { Some(NumFrac) } else { None }
    NumFrac =>
      if digit {
        Some(NumFrac)
      } else if b == 0x65 || b == 0x45 {
        Some(NumExp)
      } else {
        None
      }
    NumExp =>
      if digit {
        Some(NumExpDigits)
      } else if b == 0x2B || b == 0x2D {
        Some(NumExpSign)
      } else {
        None
      }
    NumExpSign => if digit { Some(NumExpDigits) } else { None }
    NumExpDigits => if digit { Some(NumExpDigits) } else { None }
  }
  match next {
    Some(state) => {
      self.bump_token(pos)
      self.inner.num_state = state
      self.inner.num_buf.write_char(ascii_char(b))
      true
    }
    None => {
      // 该字节仍然属于数字的一部分（`.`、`e`、`E` 或数字），只是当前状态不接受它。
      // 这类输入一律按数字词法非法处理，错误种类不随数字长度变化。
      let still_number = b == 0x2E || b == 0x65 || b == 0x45 || digit
      if still_number {
        raise ParseError::InvalidNumber(
          pos~,
          lexeme=self.inner.num_buf.to_string() + ascii_char(b).to_string(),
        )
      } else if self.num_is_terminable() {
        self.finalize_number()
        false
      } else {
        raise ParseError::InvalidNumber(
          pos~,
          lexeme=self.inner.num_buf.to_string(),
        )
      }
    }
  }
}

///|
/// 当前数字状态是否可以被分隔符合法终止。
fn Parser::num_is_terminable(self : Parser) -> Bool {
  match self.inner.num_state {
    NumZero | NumInt | NumFrac | NumExpDigits => true
    _ => false
  }
}

///|
/// 数字被分隔符确认完成。
fn Parser::finalize_number(self : Parser) -> Unit {
  let span = Span::new(self.inner.token_start, self.inner.offset)
  self.inner.events.push(
    Event::ValueComplete(
      path=self.inner.cur_path,
      value=LeafValue::Number(
        NumberLiteral::new(self.inner.num_buf.to_string()),
      ),
      span~,
    ),
  )
  self.inner.lex = LexNormal
  self.after_child()
}

///|
/// 开始读取 true / false / null。
fn Parser::begin_literal(
  self : Parser,
  kind : LitKind,
  matched : Int,
  pos : Int,
) -> Unit {
  self.inner.token_start = pos
  self.inner.token_bytes = 1
  self.inner.lex = LexLit(kind, matched)
}

///|
/// 字面量逐字匹配。
fn Parser::step_lit(
  self : Parser,
  b : Int,
  pos : Int,
  kind : LitKind,
  matched : Int,
) -> Unit raise ParseError {
  self.bump_token(pos)
  let text = match kind {
    LitTrue => "true"
    LitFalse => "false"
    LitNull => "null"
  }
  if b != text[matched].to_int() {
    raise ParseError::InvalidSyntax(pos~, expected=text, found=describe_byte(b))
  }
  if matched + 1 == text.length() {
    let value = match kind {
      LitTrue => LeafValue::Bool(true)
      LitFalse => LeafValue::Bool(false)
      LitNull => LeafValue::Null
    }
    self.inner.events.push(
      Event::ValueComplete(
        path=self.inner.cur_path,
        value~,
        span=Span::new(self.inner.token_start, pos + 1),
      ),
    )
    self.inner.lex = LexNormal
    self.after_child()
  } else {
    self.inner.lex = LexLit(kind, matched + 1)
  }
}

///|
/// 十六进制数字的值，非法返回 `None`。
fn hex_digit(b : Int) -> Int? {
  if b >= 0x30 && b <= 0x39 {
    Some(b - 0x30)
  } else if b >= 0x61 && b <= 0x66 {
    Some(b - 0x61 + 10)
  } else if b >= 0x41 && b <= 0x46 {
    Some(b - 0x41 + 10)
  } else {
    None
  }
}

///|
/// ASCII 字节转字符。调用点只传入 ASCII 字节。
fn ascii_char(b : Int) -> Char {
  match b.to_char() {
    Some(c) => c
    None => '\u{0}'
  }
}

///|
/// 错误信息里的字节描述。
fn describe_byte(b : Int) -> String {
  if b == 0x20 {
    "空格"
  } else if b == 0x09 || b == 0x0A || b == 0x0D {
    "空白"
  } else if b >= 0x21 && b <= 0x7E {
    match b.to_char() {
      Some(c) => "'\{c}'"
      None => "字节 \{b}"
    }
  } else {
    "字节 \{b}"
  }
}
