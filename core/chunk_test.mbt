// 分块不变性：同一输入的任何切分方式，必须得到同一最终文档与标准化事件序列。

///|
/// 对给定样本，断言所有切分方式与整段解析结果一致。
fn assert_chunk_invariant(
  source : String,
  splits : Array[Array[Bytes]],
) -> Unit raise {
  let bytes = utf8_bytes(source)
  let (base_events, base_result) = parse_whole(source)
  let base_doc = expect_completed(base_result)
  let base_render = render_events(normalize_events(base_events))
  inspect(bytes.length() > 0, content="true")
  for split in splits {
    let (events, result) = parse_chunks(split)
    let doc = expect_completed(result)
    inspect(doc.to_string(), content=base_doc.to_string())
    inspect(render_events(normalize_events(events)), content=base_render)
  }
}

///|
test "穷举所有单切点二分" {
  let samples = [
    "{\"a\":1}", "[1,2,3]", "{\"city\":\"上海\",\"n\":-1.5e-3}", "\"\\u4e2d\\u6587\"",
    "{\"items\":[{\"k\":\"v\"},[true,false,null]]}", "123456789012345678901234567890",
    "{\"emoji\":\"\\uD83D\\uDE00\"}", "[]", "{}", "null", "\"\"",
  ]
  for sample in samples {
    assert_chunk_invariant(sample, all_two_way_splits(utf8_bytes(sample)))
  }
}

///|
test "逐字节喂入与整段一致" {
  let samples = [
    "{\"s\":\"a\\\"b\\\\c\\u4e2d\\n\",\"n\":-0.5e+2}", "[{\"中文键\":\"中文值\"},0.001,-2e10,true,null]",
  ]
  for sample in samples {
    let bytes = utf8_bytes(sample)
    let chunks = []
    for i in 0..<bytes.length() {
      chunks.push(slice_bytes(bytes, i, i + 1))
    }
    assert_chunk_invariant(sample, [chunks])
  }
}

///|
test "固定 seed 多段随机切分" {
  let samples = [
    "{\"tool\":\"create_ticket\",\"args\":{\"title\":\"登录失败\",\"priority\":3,\"tags\":[\"bug\",\"p1\"],\"meta\":{\"ratio\":0.125,\"ok\":true,\"none\":null}}}",
    "{\"escapes\":\"\\t\\r\\n\\/\\b\\f\\\"\\\\\",\"unicode\":\"\\u0041\\u00e9\\u4e2d\\uD83D\\uDE00\"}",
  ]
  for sample in samples {
    let bytes = utf8_bytes(sample)
    let splits = []
    for seed in 0..<24 {
      splits.append(seeded_splits(bytes, seed, 2))
    }
    assert_chunk_invariant(sample, splits)
  }
}

///|
test "增量交付：字符串跨块时先出现增量再出现完成" {
  let parser = @moonstream.Parser::new()
  let first = parser.feed(utf8_bytes("{\"city\":\"上"))
  inspect(
    render_events(first),
    content=(
      #|{$@0-1 | key:city@1-7 | delta$.city=上@8-12
    ),
  )
  let second = parser.feed(utf8_bytes("海\"}"))
  inspect(
    render_events(second),
    content=(
      #|delta$.city=海@8-15 | value$.city=上海@8-16 | }$@16-17
    ),
  )
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="{\"city\":\"上海\"}")
}

///|
test "字符串增量的区间在分块边界上一致" {
  // 分块边界正好落在闭合引号上：整段解析与分块解析必须给出同一个区间。
  let source = "{\"a\":\"xy\"}"
  let bytes = utf8_bytes(source)
  let (whole_events, _) = parse_whole(source)
  let (split_events, _) = parse_chunks([
    slice_bytes(bytes, 0, 8),
    slice_bytes(bytes, 8, bytes.length()),
  ])
  let whole = render_events(normalize_events(whole_events))
  inspect(render_events(normalize_events(split_events)), content=whole)
  // 增量区间不含闭合引号，完成事件含
  inspect(whole.contains("delta$.a=xy@5-8"), content="true")
  inspect(whole.contains("value$.a=xy@5-9"), content="true")
}

///|
test "UTF-8 四字节字符跨四个块" {
  let bytes = utf8_bytes("\"𐍈\"")
  inspect(bytes.length(), content="6")
  let parser = @moonstream.Parser::new()
  let mut deltas = ""
  let mut text = ""
  for i in 0..<bytes.length() {
    for event in parser.feed(slice_bytes(bytes, i, i + 1)) {
      match event {
        @moonstream.Event::StringDelta(text=delta, ..) =>
          deltas = deltas + delta
        @moonstream.Event::ValueComplete(
          value=@moonstream.LeafValue::String(s),
          ..
        ) => text = s
        _ => ()
      }
    }
  }
  inspect(deltas, content="𐍈")
  inspect(text, content="𐍈")
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="\"𐍈\"")
}
