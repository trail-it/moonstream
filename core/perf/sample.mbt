// 基准用的样本生成器。样本内容固定，便于复现。

///|
/// 一个包含 `items` 个对象的 JSON 数组，每项都有数字、字符串、布尔与小数。
fn sample_document(items : Int) -> String {
  let out = StringBuilder()
  out.write_string("[")
  for i in 0..<items {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string(
      "{\"id\":\{i},\"name\":\"item-\{i}\",\"ok\":true,\"ratio\":0.125}",
    )
  }
  out.write_string("]")
  out.to_string()
}

///|
/// 按固定字节大小把一段字节切成若干块。
fn split_bytes(bytes : Bytes, chunk : Int) -> Array[Bytes] {
  let out = []
  let mut index = 0
  while index < bytes.length() {
    let end = if index + chunk > bytes.length() {
      bytes.length()
    } else {
      index + chunk
    }
    out.push(Bytes::from_array(bytes[index:end].to_array()))
    index = end
  }
  out
}

///|
/// 把一段输入解析完，返回事件总数（用作 `keep` 的返回值，防止被优化掉）。
fn parse_all(chunks : Array[Bytes]) -> Int raise {
  let parser = @moonstream.Parser::new()
  let mut count = 0
  for chunk in chunks {
    count = count + parser.feed(chunk).length()
  }
  let (tail, _) = parser.finish()
  count + tail.length()
}
