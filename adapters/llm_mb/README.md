# llm_mb_adapter

把 [`marianoguerra/llm`](https://mooncakes.io/docs/marianoguerra/llm)（仓库
[llm-mb](https://github.com/marianoguerra/llm-mb)）的流式事件接到
[MoonStream](../core/) 的多调用会话上。

该 SDK 把工具参数作为文本增量交付，其源码注释明确要求消费者等到 `stream_finish`
才能拿到解析结果；本适配器让调用方在流还没结束时就拿到逐字段事件。

```mbt
let adapter = @llm_mb_adapter.LlmMbAdapter::new(response_id="resp-1")
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

`ToolCallEnd` 只说明工具内容块结束。适配器会等 `Done(stop)` 决定完整性：
`EndTurn` / `ToolUse` 正常结束，`MaxTokens` / `Errored` / `Aborted` 均不可交付。

键映射：`content_index` → `CallKey.index`，`choice` 固定为 0。

## 版本固定

固定在 `marianoguerra/llm@0.1.1`。0.2.0 起该 SDK 要求 `moonbitlang/async@0.21.2`，
而本机工具链（`moon 0.1.20260713` / `moonc 0.10.4`）无法解析 async 0.21.2 的 native
源码（`noraise + nocancel`、`guard!` 等语法）；0.1.1 的 `StreamEvent` 接口与 0.3.0
完全一致，只需 `async@0.20.3`，可与其它适配模块共存。

许可证：Apache-2.0。
