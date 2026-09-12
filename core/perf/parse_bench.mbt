// 复杂度基准：输入规模、分块大小、预览投影与多调用路由。
//
// 运行：moon bench --target native --release core/bench
// 报告：core/docs/performance.md（由这些数字生成，机器信息随报告一起公布）

///|
/// 参照物：核心库 `@json.parse` 解析同一份完整文本。它不产生事件、不维护路径，
/// 因此差距就是「增量 + 事件 + 路径 + 严格校验」的代价。
test (b : @bench.T) {
  for items in [8, 64, 512, 4096] {
    let source = sample_document(items)
    let bytes = @utf8.encode(source)
    b.bench(name="core_json_\{bytes.length()}B", fn() {
      let value = try! @json.parse(source)
      b.keep(value is Json::Array(_))
    })
  }
}

///|
/// 基线：只遍历同样多的字节，不做任何解析。用来把基准框架与内存访问的开销
/// 从解析成本里分离出来。
test (b : @bench.T) {
  for items in [8, 64, 512, 4096] {
    let bytes = @utf8.encode(sample_document(items))
    b.bench(name="baseline_\{bytes.length()}B", fn() {
      let mut sum = 0
      for i in 0..<bytes.length() {
        sum = sum + bytes[i].to_int()
      }
      b.keep(sum)
    })
  }
}

///|
/// 扫描成本随输入规模的变化。理想情况下耗时应与输入字节数近似线性。
test (b : @bench.T) {
  for items in [8, 64, 512, 4096] {
    let bytes = @utf8.encode(sample_document(items))
    let chunks = [bytes]
    b.bench(name="scan_\{bytes.length()}B", fn() {
      b.keep(try! parse_all(chunks))
    })
  }
}

///|
/// 同一份输入按不同块大小喂入。块越小，调用次数越多；总字节数不变。
test (b : @bench.T) {
  let bytes = @utf8.encode(sample_document(512))
  for chunk in [1, 8, 64, 512, 4096] {
    let chunks = split_bytes(bytes, chunk)
    b.bench(name="chunk_\{chunk}B", fn() { b.keep(try! parse_all(chunks)) })
  }
}

///|
/// 部分树投影的成本（相对解析本身是额外开销）。
test (b : @bench.T) {
  let bytes = @utf8.encode(sample_document(512))
  let events = {
    let parser = @moonstream.Parser::new()
    let collected = parser.feed(bytes)
    let (tail, _) = parser.finish()
    collected.append(tail)
    collected
  }
  b.bench(name="parse_only", fn() { b.keep(try! parse_all([bytes])) })
  b.bench(name="parse_plus_preview", fn() {
    let preview = @preview.Preview::new()
    for event in events {
      try! preview.apply(event)
    }
    b.keep(preview.node_count())
  })
}

///|
/// 多调用路由：4 个**各自独立**的文档被切成片段后交错喂入，模拟一条响应里的多个 tool call。
test (b : @bench.T) {
  let fragments : Array[Array[Bytes]] = [
    split_bytes(@utf8.encode(sample_document(16)), 32),
    split_bytes(@utf8.encode(sample_document(16)), 32),
    split_bytes(@utf8.encode(sample_document(16)), 32),
    split_bytes(@utf8.encode(sample_document(16)), 32),
  ]
  let steps = fragments[0].length()
  b.bench(name="session_4calls", fn() {
    let session = try! @session.Session::new()
    for step in 0..<steps {
      for slot in 0..<4 {
        let key = @session.CallKey::new(response="r", choice=0, index=slot)
        try! session.open(key)
        b.keep(try! session.feed(key, fragments[slot][step]).length())
      }
    }
  })
}

///|
/// 每 MB 输入产生的事件数（吞吐口径的一部分，不是时间）。
test {
  for items in [8, 64, 512, 4096] {
    let bytes = @utf8.encode(sample_document(items))
    let events = parse_all([bytes])
    let per_kb = events * 1024 / bytes.length()
    println(
      "\{bytes.length()} 字节 -> \{events} 个事件（约 \{per_kb} 个/KiB）",
    )
  }
}
