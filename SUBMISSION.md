# MoonStream 项目申报书

**基本信息**

- 项目名称：MoonStream：MoonBit LLM 流式 JSON 增量解析引擎
- 参赛者：涂志鸿；
- GitHub 仓库链接：[https://github.com/trail-it/moonstream](https://github.com/trail-it/moonstream)
- Mooncakes 主包：`trail-it/moonstream`
- 项目方向：MoonBit AI 基础设施 / 流式结构化输出解析
- 是否为移植项目：否，为原创项目

**项目简介**

MoonStream 为 MoonBit 应用提供 LLM tool-call 参数的字节级增量解析能力。模型返回参数时，应用收到的通常是未闭合 JSON 片段，还要面对跨块 UTF-8、半个数字、截断流和多个工具调用交错等问题。MoonStream 在片段到达时输出结构事件、已完成字段和部分树预览，并通过明确的完成契约阻止应用把不完整内容误当成最终结果。它可用于 Agent 工具调用、结构化表单、工单草稿和实时生成界面。

**核心功能范围**

- 提供严格的字节级增量 JSON 状态机，支持任意分块、跨块 UTF-8、转义字符及嵌套对象和数组；
- 输出对象、数组、键名、字符串增量和叶值完成事件，使字段在整篇文档结束前即可安全使用；
- 提供 `Preview` 部分树，区分缺失、生成中、未闭合字符串、完整值和 JSON `null`；
- 提供 `Completed`、`Incomplete`、`Aborted` 终态，只有正常流结束且 JSON 完整时才交付文档；
- 提供 `Session` 多调用路由，按响应、选择和调用索引隔离交错的 tool call，单个调用失败不影响其他结果；
- 在仓库中提供 marianoguerra/llm、mizchi/llm 和 DC-Z-lab/moonllm 的适配示例；
- 提供 Native 消费者、CLI 离线回放和 wasm-gc 浏览器演示，并以 CI 覆盖检查、构建和测试。

**原创或参考说明**：本项目没有移植其他语言解析器。现有 MoonBit LLM SDK 负责模型通信和文本增量，JSON/JSONL 库主要处理完整文档；MoonStream 新增半成品 JSON 的严格语义、分块不变性、多调用隔离和可测试的结束契约。适配示例仅使用三个 SDK 的公开事件类型，来源和许可证记录在 `THIRD_PARTY.md`；本项目采用 Apache-2.0 许可证。

**实施与交付**：核心解析器、预览、会话路由、示例、文档和测试已经完成，`trail-it/moonstream` 0.1.1 已发布。当前本地验证为 Native 131 项、JS 124 项、wasm-gc 124 项测试及 17 项演示检查全部通过。后续完成 Gitlink 同步、真实 SDK 接入反馈，并持续维护工具链与上游 SDK 兼容性。
