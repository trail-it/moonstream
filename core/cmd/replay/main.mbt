// 离线回放工具：把一段 JSON 文本按固定字节大小分块喂入解析器，
// 打印每个块产生的事件与最终完整性判断。
//
// 用法（native）：
//   moon run --target native cmd/replay
//   moon run --target native cmd/replay -- '{"a":1}' 3
//
// 不联网、不调用模型：样本来自命令行或内置常量，因此可重复复现。

///|
/// 内置样本：一条典型的工具调用参数流。
fn default_sample() -> String {
  "{\"tool\":\"create_ticket\",\"args\":{\"title\":\"登录失败\",\"priority\":3,\"tags\":[\"bug\",\"p1\"],\"meta\":{\"ratio\":0.125,\"ok\":true,\"note\":null}}}"
}

///|
/// 解析块大小；非法输入回退到 8。
fn parse_chunk_size(text : String) -> Int {
  try {
    let size = @str.parse_int(text)
    if size > 0 {
      size
    } else {
      8
    }
  } catch {
    _ => 8
  } noraise {
    size => size
  }
}

///|
/// 解析命令行参数：`[程序名, 文本?, 块大小?]`。
fn parse_args() -> (String, Int) {
  let args = @env.args()
  let source = match args.get(1) {
    Some(text) => text
    None => default_sample()
  }
  let chunk_size = match args.get(2) {
    Some(text) => parse_chunk_size(text)
    None => 8
  }
  (source, chunk_size)
}

///|
/// 打印一个块产生的事件。
fn print_events(events : Array[@moonstream.Event]) -> Unit {
  for event in events {
    match event {
      @moonstream.Event::ObjectBegin(path~, ..) =>
        println("  {  \{path.to_string()}")
      @moonstream.Event::ObjectEnd(path~, ..) =>
        println("  }  \{path.to_string()}")
      @moonstream.Event::ArrayBegin(path~, ..) =>
        println("  [  \{path.to_string()}")
      @moonstream.Event::ArrayEnd(path~, ..) =>
        println("  ]  \{path.to_string()}")
      @moonstream.Event::KeyComplete(name~, ..) => println("  key   \{name}")
      @moonstream.Event::StringDelta(path~, text~, ..) =>
        println("  delta \{path.to_string()} = \{text}")
      @moonstream.Event::ValueComplete(path~, value~, ..) =>
        println("  value \{path.to_string()} = \{render_value(value)}")
    }
  }
}

///|
/// 叶值的可读文本。
fn render_value(value : @moonstream.LeafValue) -> String {
  match value {
    @moonstream.LeafValue::Null => "null"
    @moonstream.LeafValue::Bool(b) => b.to_string()
    @moonstream.LeafValue::Number(n) => n.lexeme()
    @moonstream.LeafValue::String(s) => "\"" + s + "\""
  }
}

///|
/// 打印最终结果。
fn print_result(result : @moonstream.FinishResult) -> Unit {
  match result {
    @moonstream.FinishResult::Completed(doc) =>
      println("结果: Completed，共 \{doc.byte_length()} 字节")
    @moonstream.FinishResult::Incomplete(pos~, expected~) =>
      println("结果: Incomplete（位置 \{pos}，期待 \{expected}）")
    @moonstream.FinishResult::Aborted(reason~) =>
      println("结果: Aborted（\{to_repr(reason)}）")
  }
}

///|
fn main {
  let (source, chunk_size) = parse_args()
  let bytes = @utf8.encode(source)
  println("输入: \{bytes.length()} 字节，分块大小 \{chunk_size}")
  // 默认限制不可能非法，这里的 try! 只在不可达情况下终止。
  let parser = try! @moonstream.Parser::new()
  let mut index = 0
  let mut block = 0
  while index < bytes.length() {
    let end = if index + chunk_size > bytes.length() {
      bytes.length()
    } else {
      index + chunk_size
    }
    let chunk = Bytes::from_array(bytes[index:end].to_array())
    block = block + 1
    println("块 \{block}（字节 \{index}..\{end}）")
    let fed = Ok(parser.feed(chunk)) catch { err => Err(err) }
    match fed {
      Ok(events) => print_events(events)
      Err(err) => {
        println("解析错误: \{to_repr(err)}")
        return
      }
    }
    index = end
  }
  let finished = Ok(parser.finish()) catch { err => Err(err) }
  match finished {
    Ok((tail, result)) => {
      if tail.length() > 0 {
        println("收尾事件")
        print_events(tail)
      }
      print_result(result)
    }
    Err(err) => println("解析错误: \{to_repr(err)}")
  }
}
