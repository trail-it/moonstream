# moonllm_adapter

把 [`DC-Z-lab/moonllm`](https://mooncakes.io/docs/DC-Z-lab/moonllm) 的流式 chunk 接到
[MoonStream](../core/) 的多调用会话上。

该 SDK 的 `ToolCallAccumulator` 把参数片段拼进 `StringBuilder`，等到 `finish` 才给出完整字符串；
`ToolCallDelta.arguments` 正是本库要消费的「参数文本片段」。本适配器把每个片段直接送进
`Session`，于是同一个流的消费方不必再自己维护一套拼接与部分解析。

```mbt
let adapter = @moonllm_adapter.MoonllmAdapter::new(response_id="chatcmpl-1")
for chunk in chunks {
  for update in adapter.apply(chunk).updates() {
    render(update.key, update.events)
    match update.failure {
      Some(error) => report_error(update.key, error)
      None => ()
    }
    match update.result {
      Some(result) => deliver(update.key, result)
      None => ()
    }
  }
}
```

适配器会读取最终 chunk 的 `finish_reason` 并自动结束所有打开的调用。若上游在没有最终 chunk
的情况下断开，调用方必须显式使用 `finish_all(reason=EndReason::Truncated)`；该方法返回的
每个 `CallUpdate` 都保留 CallKey、收尾事件和结果。

键映射：`ToolCallDelta.index` → `CallKey.index`，`choice` 固定为 0
（该 SDK 的 `parse_stream_data` 只读取 `choices[0]`）。

## 后端与版本约束

- 固定 `DC-Z-lab/moonllm@0.1.0`，它依赖 `oboard/mio@0.5.2` 与 `moonbitlang/async@0.20.1`。
- 该 SDK 只支持 **native**，因此这个适配模块声明 `supported_targets = "native"`，
  在 js / wasm-gc 下会被自动跳过。
- 它单独成一个模块：与 `marianoguerra/llm`（需要更新的 async）放在同一个模块里会产生
  依赖版本冲突。

许可证：Apache-2.0。
