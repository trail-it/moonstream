// 演示状态与对外接口。
//
// 对外只暴露整数接口（wasm-gc 的 Int 是 i32）：渲染结果以 UTF-16 码元序列
// 逐字符读出，避免跨边界传字符串带来的 ABI 依赖。

///|
/// 内置样本：一条典型的工具调用参数流。
fn sample_source() -> String {
  "{\"tool\":\"create_ticket\",\"args\":{\"title\":\"登录失败\",\"priority\":3,\"tags\":[\"bug\",\"p1\"],\"meta\":{\"ratio\":0.125,\"ok\":true,\"note\":null}}}"
}

///|
/// 演示状态。结构体是引用类型，所以可以当作可变的单例使用。
priv struct Demo {
  source : String
  mut chunk_size : Int
  mut offset : Int
  mut step : Int
  mut total_steps : Int
  mut status : String
  mut detail : String
  mut log : Array[String]
  mut parser : @moonstream.Parser
  mut preview : @preview.Preview
  mut last_chunk : String
}

///|
let demo : Demo = {
  source: sample_source(),
  chunk_size: 8,
  offset: 0,
  step: 0,
  total_steps: 0,
  status: "parsing",
  detail: "",
  log: [],
  parser: try! @moonstream.Parser::new(),
  preview: @preview.Preview::new(),
  last_chunk: "",
}

///|
/// 重新开始。
fn reset_demo() -> Unit {
  demo.offset = 0
  demo.step = 0
  demo.status = "parsing"
  demo.detail = ""
  demo.log = []
  demo.last_chunk = ""
  demo.parser = try! @moonstream.Parser::new()
  demo.preview = @preview.Preview::new()
  let total = @utf8.encode(demo.source).length()
  demo.total_steps = (total + demo.chunk_size - 1) / demo.chunk_size
}

///|
/// 渲染单个事件为一行可读文本。
fn render_event(event : @moonstream.Event) -> String {
  let path = event.path().to_string()
  match event {
    @moonstream.Event::ObjectBegin(..) => "{\{path}   对象开始"
    @moonstream.Event::ObjectEnd(..) => "}\{path}   对象结束"
    @moonstream.Event::ArrayBegin(..) => "[\{path}   数组开始"
    @moonstream.Event::ArrayEnd(..) => "]\{path}   数组结束"
    @moonstream.Event::KeyComplete(name~, ..) => "key  \{path} = \{name}"
    @moonstream.Event::StringDelta(text~, ..) => "…    \{path} += \{text}"
    @moonstream.Event::ValueComplete(value~, ..) =>
      "✓    \{path} = \{render_value(value)}"
  }
}

///|
fn render_value(value : @moonstream.LeafValue) -> String {
  match value {
    @moonstream.LeafValue::Null => "null"
    @moonstream.LeafValue::Bool(b) => b.to_string()
    @moonstream.LeafValue::Number(n) => n.lexeme()
    @moonstream.LeafValue::String(s) => "\"" + s + "\""
  }
}

///|
/// JSON 字符串转义。
fn json_escape(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// 把一个字符串写成 JSON 数组元素。
fn json_string(text : String) -> String {
  "\"" + json_escape(text) + "\""
}

///|
/// 当前状态序列化成 JSON。
fn render_state() -> String {
  let out = StringBuilder()
  out.write_string("{\"step\":")
  out.write_string(demo.step.to_string())
  out.write_string(",\"total_steps\":")
  out.write_string(demo.total_steps.to_string())
  out.write_string(",\"chunk_size\":")
  out.write_string(demo.chunk_size.to_string())
  out.write_string(",\"status\":")
  out.write_string(json_string(demo.status))
  out.write_string(",\"detail\":")
  out.write_string(json_string(demo.detail))
  out.write_string(",\"last_chunk\":")
  out.write_string(json_string(demo.last_chunk))
  out.write_string(",\"source\":")
  out.write_string(json_string(demo.source))
  out.write_string(",\"preview\":")
  out.write_string(json_string(demo.preview.to_preview_string()))
  out.write_string(",\"log\":[")
  let mut first = true
  for line in demo.log {
    if !first {
      out.write_string(",")
    }
    first = false
    out.write_string(json_string(line))
  }
  out.write_string("]}")
  out.to_string()
}

///|
/// 渲染结果缓存，供 `render_char` 逐字符读取。
let render_buffer : StringBuilder = StringBuilder()

///|
/// 把当前状态写进缓冲区。
fn refresh_buffer() -> Unit {
  render_buffer.reset()
  render_buffer.write_string(render_state())
}

///|
/// 重新开始演示。
pub fn demo_reset() -> Unit {
  reset_demo()
  refresh_buffer()
}

///|
/// 设置分块大小（字节）。非法值回退到 8。
pub fn demo_set_chunk_size(size : Int) -> Unit {
  demo.chunk_size = if size > 0 && size <= 64 { size } else { 8 }
  reset_demo()
  refresh_buffer()
}

///|
/// 推进一个分块。返回该块产生的事件数；`-1` 表示解析错误，`0` 表示已到末尾。
pub fn demo_step() -> Int {
  try step_inner() catch {
    err => {
      demo.status = "error"
      demo.detail = "\{Debug::to_repr(err)}"
      refresh_buffer()
      -1
    }
  } noraise {
    count => count
  }
}

///|
fn step_inner() -> Int raise {
  if demo.status != "parsing" {
    return 0
  }
  let bytes = @utf8.encode(demo.source)
  let total = bytes.length()
  if demo.offset >= total {
    return 0
  }
  let end = if demo.offset + demo.chunk_size > total {
    total
  } else {
    demo.offset + demo.chunk_size
  }
  let chunk = Bytes::from_array(bytes[demo.offset:end].to_array())
  demo.last_chunk = @utf8.decode_lossy(chunk)
  let events = demo.parser.feed(chunk)
  for event in events {
    demo.preview.apply(event)
    demo.log.push(render_event(event))
  }
  demo.offset = end
  demo.step = demo.step + 1
  if demo.offset >= total {
    let (tail, result) = demo.parser.finish()
    for event in tail {
      demo.preview.apply(event)
      demo.log.push(render_event(event))
    }
    match result {
      @moonstream.FinishResult::Completed(doc) => {
        demo.status = "complete"
        demo.detail = doc.to_string()
      }
      @moonstream.FinishResult::Incomplete(expected~, ..) => {
        demo.status = "incomplete"
        demo.detail = expected
      }
      @moonstream.FinishResult::Aborted(reason~) => {
        demo.status = "aborted"
        demo.detail = "\{Debug::to_repr(reason)}"
      }
    }
  }
  refresh_buffer()
  events.length()
}

///|
/// 用截断原因结束，用来演示「预览保留但不可交付」。
pub fn demo_truncate() -> Unit {
  if demo.status != "parsing" {
    return
  }
  try truncate_inner() catch {
    err => {
      demo.status = "error"
      demo.detail = "\{Debug::to_repr(err)}"
    }
  } noraise {
    _ => ()
  }
  refresh_buffer()
}

///|
fn truncate_inner() -> Unit raise {
  let (tail, result) = demo.parser.finish(
    reason=@moonstream.EndReason::Truncated,
  )
  for event in tail {
    demo.preview.apply(event)
    demo.log.push(render_event(event))
  }
  match result {
    @moonstream.FinishResult::Completed(_) => demo.status = "complete"
    @moonstream.FinishResult::Incomplete(expected~, ..) => {
      demo.status = "incomplete"
      demo.detail = expected
    }
    @moonstream.FinishResult::Aborted(reason~) => {
      demo.status = "aborted"
      demo.detail = "\{Debug::to_repr(reason)}"
    }
  }
}

///|
/// 渲染结果长度（UTF-16 码元数）。
pub fn demo_render_len() -> Int {
  render_buffer.to_string().length()
}

///|
/// 取渲染结果的第 i 个 UTF-16 码元；越界返回 -1。
pub fn demo_render_char(index : Int) -> Int {
  let text = render_buffer.to_string()
  if index < 0 || index >= text.length() {
    return -1
  }
  text[index].to_int()
}
