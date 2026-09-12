# SDK 适配契约

核心只消费参数字节。每个 SDK 独立成模块，主库没有 SDK 依赖。

| SDK 固定版本 | 调用键来源 | 正常结束信号 |
|---|---|---|
| marianoguerra/llm 0.1.1 | content_index | Done(EndTurn / ToolUse) |
| mizchi/llm 0.3.1 | 字符串 id 按首次出现分配序号 | MessageEnd(Stop / ToolUse) |
| DC-Z-lab/moonllm 0.1.0 | ToolCallDelta.index | chunk.finish_reason 为 stop / end_turn / tool_calls / tool_use |

ToolCallEnd 只表示内容块结束。必须等待响应级终止原因；长度限制、错误、过滤和未知结束原因
不能交付 Completed。无结束信号的断流必须由调用方显式传 Truncated，主动取消传 Cancelled。
适配器实例只用于一次响应。

## 输出与错误

AdapterOutcome::updates() 返回 Array[CallUpdate]。每条更新包含：

- key：稳定的 (response, choice, index)，用来选择独立的 Preview。
- events：这个调用的事件，包含正常收尾产生的末尾数字事件。
- result：None 表示没有结束结果；Some(Completed / Incomplete / Aborted) 表示已经收尾。
- failure：收尾时解析失败的 SessionError；失败更新的 result 为 None。

不要把不同 key 的 events 展平后送进同一棵 Preview。消费时先处理 events，再分别处理 result
和 failure；只有 Completed 才能作为完整文档继续做 Schema / 业务验证。

@adapter.finish_open(session, reason) 按注册顺序收尾，逐调用捕获错误，因此中间调用的
未完成 UTF-8 在 finish 时失败，不会吞掉前一个调用的结果或阻止后一个调用收尾。
此前已由 feed 抛错的调用不再进入 open_calls；原始错误保存在 Session::failure(key)。
单次 apply 的 feed / 元数据错误仍通过抛出 SessionError 报告，调用方必须处理这一通道。

## 接入步骤

1. 根据 SDK 的 id / index 建立 CallKey，响应和 choice 的命名空间由应用提供。
2. 使用 session.open(key, id=Some(id), name=Some(name)) 注册元数据。
3. 使用 session.feed(key, @utf8.encode(fragment))，将返回事件包装为 CallUpdate::delta。
4. 收到可靠终止原因后调用 @adapter.finish_open(session, reason)，保留全部更新。

具体可编译实现与真实 SDK 类型测试见仓库的 adapters/llm_mb、adapters/mizchi_llm、adapters/moonllm。
这些测试验证适配类型和事件序列，并不代表已经向真实模型服务发起在线请求。

## 兼容与回归

固定依赖版本的构造器来源见各模块 manifest。升级 SDK 或工具链后需重新验证，不能仅凭
构造器名称一致断言行为兼容。回归至少涵盖：交错调用、同路径不同 key、完整 JSON 遇 Length、
消息错误、末尾数字收尾以及单调用失败时其他调用能继续结束。

## 未发布 API 迁移

旧的 Delta / Finished 和无键 events() 已替换为 Updates 与 updates()；按 update.key 路由。
手动 finish_call / finish_slot / finish_all 要求显式 reason。新增 failure 字段必须纳入错误处理。
