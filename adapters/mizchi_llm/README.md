# mizchi_llm_adapter

把 [`mizchi/llm`](https://mooncakes.io/docs/mizchi/llm)（生态里下载量最高的 MoonBit LLM 客户端）
的流式事件接到 [MoonStream](../core/) 的多调用会话上。

该 SDK 用字符串 `id` 标识工具调用，参数以文本增量交付：

```moonbit
ToolCallStart(id~ : String, name~ : String)
ToolCallDelta(id~ : String, input_delta~ : String)
ToolCallEnd(id~ : String, name~ : String, input~ : Json)
```

本适配器按 id 首次出现的顺序把它映射成 `CallKey.index`，因此同一条流里 id 与序号一一对应；
`ToolCallEnd` 携带的 `input` 是 SDK 自己解析好的 `Json`，可以直接用来对照本库产出的
`CompletedDocument`。

```mbt
let adapter = @mizchi_llm_adapter.MizchiLlmAdapter::new(response_id="resp-1")
for event in stream_events {
  match adapter.apply(event) {
    @adapter.AdapterOutcome::Ignored => ()
    @adapter.AdapterOutcome::Updates(updates~) =>
      for update in updates {
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
}
```

`ToolCallEnd` 只说明工具内容块结束。适配器会等随后的 `MessageEnd(finish_reason)`：
只有 `Stop` / `ToolUse` 可以产生 `Completed`，`Length`、内容过滤、错误和未知原因均为 `Aborted`。

## 版本固定

固定在 `mizchi/llm@0.3.1`：该版本**没有任何依赖**，`StreamEvent` 接口与 0.3.2 完全一致。
0.3.2 引入了 `moonbitlang/async@0.20.5`，而本机工具链（`moon 0.1.20260713` /
`moonc 0.10.4`）无法解析 async 0.20.5 的 native 源码。

许可证：Apache-2.0。
