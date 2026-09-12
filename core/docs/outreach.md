# 生态反馈：接触对象与消息草稿

> **状态：一份都没发出。** 按项目提案的约定，未经作者明确授权不主动发消息或开 issue。
> 本文只是把"如果发，发给谁、发什么、拿什么证据"准备好，方便一次授权后执行。

## 为什么要接触

M1–M3 交付的是"我们能做出来"，还缺"别人确实需要"。需要的是**一个外部消费者**的真实使用反馈，
而不是自我评估。最低目标是：两个现有 SDK 的维护者里，至少一位确认"这个能力有用/接口可接受"，
或者指出我们漏掉的场景。

## 候选对象（按优先级）

| # | 对象 | 为什么是他 | 我们手上有的事实 |
|---|---|---|---|
| 1 | [`marianoguerra/llm-mb`](https://github.com/marianoguerra/llm-mb) 作者 | 其源码注释明确写着"参数以文本增量到达，想要解析就等 `stream_finish`"——这正是我们补的缺口 | 仓库里已有 `adapters/llm_mb`，用其真实 `StreamEvent` 通过测试 |
| 2 | [`mizchi/llm`](https://github.com/mizchi/llm) 作者 | 生态里下载量最高的 MoonBit LLM 客户端；`ToolCallDelta(input_delta)` 与我们的事件模型直接对应 | `adapters/mizchi_llm`，并用其 `ToolCallEnd.input : Json` 交叉验证过结果 |
| 3 | [`DC-Z-lab/moonllm`](https://github.com/DC-Z-lab/moonllm) 作者 | 提供 `ToolCallAccumulator`（拼接）但没有部分解析；native-only | `adapters/moonllm`，用其真实 `StreamChunk` 通过测试 |
| 4 | `moonbitlang/awesome-moonbit` 维护者 | 生态项目列表入口 | 需要先有发布版本与外部反馈 |
| 5 | `moonbit-community/Community-Tasks` | 社区任务与协作入口 | 同上 |

**不要**同时给所有人发同一封模板信。一次只接触一位，且只在对方明确表示感兴趣后继续。

## 消息草稿（给适配层的 SDK 维护者）

> 主题：MoonStream —— 给流式 tool-call 参数补一层增量解析（已适配你的 SDK）
>
> 你好，
>
> 我在 MoonBit 里做了一个库 MoonStream，专门处理你 SDK 里"参数以文本增量到达"这一层：
> 它消费已经提取出来的参数片段字节，跨片段保存语法状态，在流还没结束时就能给出逐字段事件，
> 并在正常结束时才产出一个可交付的完整文档。
>
> 我为 `<SDK 名>` 写了一个适配层，直接用你仓库里的 `StreamEvent` / `StreamChunk` 类型驱动，
> 测试覆盖了两个调用交错、截断、id 冲突这些情况。仓库：`<链接>`，适配层：`<路径>`。
>
> 想请你判断两件事：
> 1. 这个能力对你的使用者是否有意义？还是你觉得应该留在 SDK 内部？
> 2. 如果放进 SDK，你希望的接口形状是什么样的？
>
> 不需要你承诺任何事；如果你觉得方向不对，直接说就行，我会按你的反馈调整或收手。

发送前替换 `<SDK 名>`、`<链接>`、`<路径>`，并**先自己跑一遍** `node demo/check.mjs` 确保示例可复现。

## 需要一起给出的证据

- 一个可复现的离线演示（`demo/`），不依赖网络。
- 适配层的测试文件（用对方 SDK 的真实类型）。
- `core/docs/semantics.md` 里"我们承诺什么、不承诺什么"。
- `core/docs/performance.md` 的实测数字（不要口头给"更快"）。

## 拿到反馈之后

1. 把反馈**原样**记到 `core/docs/feedback.md`（新文件），注明日期、来源、是否匿名。
2. 能修的做成 issue/PR，并在 `CHANGELOG.md` 引用。
3. 只有在对方明确说"我们在用/我们打算用"之后，才可以在 README 里写"已被 X 采用"。
   **官方推荐、生态列表收录由对方决定，不能自授。**
