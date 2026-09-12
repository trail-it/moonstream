// 前缀行为：只有本身已经构成完整 JSON 文档的前缀才可能正常 finish 成功。

///|
/// 用官方 JSON 解析器作为独立 oracle：该文本本身是否是一个完整 JSON 文档。
fn is_complete_json(text : String) -> Bool {
  try {
    let _ = @json.parse(text)
    true
  } catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
test "每个字节前缀的 finish 结果与独立 oracle 一致" {
  let samples = [
    "{\"a\":1}", "[1,2]", "\"x\"", "12", "true", "null", "{\"a\":{\"b\":[1]}}", "  {\"a\" : [1 , 2] }  ",
    "{}", "[]",
  ]
  for sample in samples {
    let bytes = utf8_bytes(sample)
    for i in 0..<=bytes.length() {
      let prefix = slice_bytes(bytes, 0, i)
      let text = @utf8.decode_lossy(prefix)
      let parser = @moonstream.Parser::new()
      let _ = parser.feed(prefix)
      let (_, result) = parser.finish()
      let ours = match result {
        @moonstream.FinishResult::Completed(_) => true
        _ => false
      }
      assert_eq(ours, is_complete_json(text))
    }
  }
}

///|
test "未完成的前缀给出位置与期待内容" {
  let parser = @moonstream.Parser::new()
  let _ = parser.feed(utf8_bytes("{\"city\":\"上海\",\"count\":"))
  let (_, result) = parser.finish()
  match result {
    @moonstream.FinishResult::Incomplete(pos~, expected~) => {
      inspect(pos, content="25")
      inspect(expected, content="值")
    }
    _ => fail("应当为 Incomplete")
  }
}

///|
test "恰好完整的文档不会因为分块而变成 Incomplete" {
  let bytes = utf8_bytes("[1,2,3]")
  let parser = @moonstream.Parser::new()
  for i in 0..<bytes.length() {
    let _ = parser.feed(slice_bytes(bytes, i, i + 1))
  }
  let (_, result) = parser.finish()
  let doc = expect_completed(result)
  inspect(doc.to_string(), content="[1,2,3]")
}
