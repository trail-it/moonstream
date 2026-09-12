// 测试公共工具：分块喂入、事件标准化、确定性切分生成。

///|
/// 字符串按 UTF-8 编码为字节。
fn utf8_bytes(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
/// 取字节区间。
fn slice_bytes(bytes : Bytes, start : Int, end : Int) -> Bytes {
  Bytes::from_array(bytes[start:end].to_array())
}

///|
/// 按给定分块喂入，返回全部事件（含收尾事件）与 finish 结果。
fn parse_chunks(
  chunks : Array[Bytes],
) -> (Array[@moonstream.Event], @moonstream.FinishResult) raise {
  let parser = @moonstream.Parser::new()
  let events = []
  for chunk in chunks {
    events.append(parser.feed(chunk))
  }
  let (tail, result) = parser.finish()
  events.append(tail)
  (events, result)
}

///|
/// 一次性喂入整段文本。
fn parse_whole(
  s : String,
) -> (Array[@moonstream.Event], @moonstream.FinishResult) raise {
  parse_chunks([utf8_bytes(s)])
}

///|
/// 取出完成结果，否则让测试失败。
fn expect_completed(
  result : @moonstream.FinishResult,
) -> @moonstream.CompletedDocument raise {
  match result {
    @moonstream.FinishResult::Completed(doc) => doc
    @moonstream.FinishResult::Incomplete(pos~, expected~) =>
      fail(
        "期待 Completed，实际 Incomplete(pos=\{pos}, expected=\{expected})",
      )
    @moonstream.FinishResult::Aborted(reason~) =>
      fail("期待 Completed，实际 Aborted(reason=\{to_repr(reason)})")
  }
}

///|
/// 把相邻同路径的字符串增量合并，得到与分块方式无关的标准化事件序列。
fn normalize_events(
  events : Array[@moonstream.Event],
) -> Array[@moonstream.Event] {
  let out = []
  for event in events {
    let merged = match (out.last(), event) {
      (
        Some(
          @moonstream.Event::StringDelta(
            path=prev_path,
            text=prev_text,
            span=prev_span
          )
        ),
        @moonstream.Event::StringDelta(path~, text~, span~),
      ) =>
        if prev_path == path {
          Some(
            @moonstream.Event::StringDelta(
              path~,
              text=prev_text + text,
              span=@moonstream.Span::new(prev_span.start, span.end),
            ),
          )
        } else {
          None
        }
      _ => None
    }
    match merged {
      Some(event) => out[out.length() - 1] = event
      None => out.push(event)
    }
  }
  out
}

///|
/// 穷举一个字节串的所有单切点二分。
fn all_two_way_splits(bytes : Bytes) -> Array[Array[Bytes]] {
  let out = []
  for i in 0..<=bytes.length() {
    out.push([slice_bytes(bytes, 0, i), slice_bytes(bytes, i, bytes.length())])
  }
  out
}

///|
/// 固定 seed 的多段切分：切块大小在候选集合中循环，便于复现。
fn seeded_splits(
  bytes : Bytes,
  seed : Int,
  rounds : Int,
) -> Array[Array[Bytes]] {
  let sizes = [1, 2, 3, 5, 7, 11, 13, 17]
  let out = []
  for round in 0..<rounds {
    let chunks = []
    let mut index = 0
    let mut cursor = (seed + round * 5) % sizes.length()
    while index < bytes.length() {
      let size = sizes[cursor % sizes.length()]
      let next = if index + size > bytes.length() {
        bytes.length()
      } else {
        index + size
      }
      chunks.push(slice_bytes(bytes, index, next))
      index = next
      cursor = cursor + 1
    }
    out.push(chunks)
  }
  out
}

///|
/// 事件序列的紧凑文本，便于断言。
fn render_events(events : Array[@moonstream.Event]) -> String {
  let out = []
  for event in events {
    out.push(render_event(event))
  }
  out.join(" | ")
}

///|
/// 单个事件的紧凑文本。
fn render_event(event : @moonstream.Event) -> String {
  // 区间也进渲染结果：分块不变性必须连 span 一起验证，否则区间口径的偏差
  // （例如增量事件是否含闭合引号）会被测试放过。
  let span = event.span()
  let at = "@\{span.start}-\{span.end}"
  match event {
    @moonstream.Event::ObjectBegin(path~, ..) => "{\{path.to_string()}\{at}"
    @moonstream.Event::ObjectEnd(path~, ..) => "}\{path.to_string()}\{at}"
    @moonstream.Event::ArrayBegin(path~, ..) => "[\{path.to_string()}\{at}"
    @moonstream.Event::ArrayEnd(path~, ..) => "]\{path.to_string()}\{at}"
    @moonstream.Event::KeyComplete(name~, ..) => "key:\{name}\{at}"
    @moonstream.Event::StringDelta(path~, text~, ..) =>
      "delta\{path.to_string()}=\{text}\{at}"
    @moonstream.Event::ValueComplete(path~, value~, ..) =>
      "value\{path.to_string()}=\{render_value(value)}\{at}"
  }
}

///|
/// 叶值的紧凑文本。
fn render_value(value : @moonstream.LeafValue) -> String {
  match value {
    @moonstream.LeafValue::Null => "null"
    @moonstream.LeafValue::Bool(b) => b.to_string()
    @moonstream.LeafValue::Number(n) => n.lexeme()
    @moonstream.LeafValue::String(s) => s
  }
}
