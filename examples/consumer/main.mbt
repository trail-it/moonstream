// 最小消费者示例。
//
// 演示三件事：
//   1. 参数片段逐块到达时，已完成的字段立刻可用；
//   2. 半个汉字跨块也能正确拼接（第 2 块只有汉字的前半个字节）；
//   3. 只有正常结束才得到可交付结果，中途只有预览。

///|
fn main {
  try run() catch {
    err => println("解析失败: \{Debug::to_repr(err)}")
  } noraise {
    _ => ()
  }
}

///|
fn run() -> Unit raise {
  let parser = @moonstream.Parser::new()
  let preview = @preview.Preview::new()
  // 第 2 块是「上」的第一个字节，故意切开一个 UTF-8 字符
  let chunks = [b"{\"city\":\"", b"\xe4", b"\xb8\x8a海\",\"count\":12}"]
  for chunk in chunks {
    for event in parser.feed(chunk) {
      preview.apply(event)
      match event {
        @moonstream.Event::ValueComplete(path~, value~, ..) =>
          println("完成字段 \{path.to_string()} = \{render(value)}")
        _ => ()
      }
    }
    println("  当前预览: \{preview.to_preview_string()}")
  }
  let (_, result) = parser.finish()
  match result {
    @moonstream.FinishResult::Completed(doc) =>
      println("可交付: \{doc.to_string()}（\{doc.byte_length()} 字节）")
    @moonstream.FinishResult::Incomplete(..) =>
      println("不可交付：还没写完")
    @moonstream.FinishResult::Aborted(..) =>
      println("不可交付：非正常结束")
  }
}

///|
fn render(value : @moonstream.LeafValue) -> String {
  match value {
    @moonstream.LeafValue::Null => "null"
    @moonstream.LeafValue::Bool(b) => b.to_string()
    @moonstream.LeafValue::Number(n) => n.lexeme()
    @moonstream.LeafValue::String(s) => s
  }
}
