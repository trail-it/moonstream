# MoonStream 项目申报书
项目名称：MoonStream
项目仓库：https://github.com/trail-it/moonstream
Gitlink 仓库：待创建并与 GitHub 默认分支同步
Mooncakes：`trail-it/moonstream`、`trail-it/llm_mb_adapter`、`trail-it/mizchi_llm_adapter`、`trail-it/moonllm_adapter`
项目类型：原创 MoonBit 基础库；适配已有 SDK 的公开事件类型，不移植其他语言代码
一句话介绍：一个为 MoonBit 生态提供 LLM 流式结构化输出增量解析与完整性契约的开源项目。

## 背景与价值
MoonBit 的 LLM SDK 已能持续返回 tool-call 参数片段，但应用仍需自行处理未闭合 JSON、跨块 UTF-8、截断流和多调用交错。MoonStream 把这层能力沉淀为独立基础库，使界面能安全预览字段，同时明确区分“当前可见内容”和“最终可交付文档”。

## 核心功能
1. 字节级增量 JSON 状态机，支持任意分块和跨块 UTF-8。
2. 输出结构事件、已完成叶值、部分树预览及 `Completed/Incomplete/Aborted` 终态。
3. `Session` 按响应、选择和调用索引隔离并发 tool call，单次失败不丢失其他结果。
4. 提供 marianoguerra/llm、mizchi/llm、DC-Z-lab/moonllm 三个独立适配器。
5. 提供 Native 消费者、离线回放工具及 wasm-gc 浏览器演示。

## 独立贡献与生态差异
现有 SDK 负责模型通信和文本增量，JSON/JSONL 库面向完整文档；本项目新增半成品 JSON 的严格语义、分块不变性、调用隔离和可测试的结束契约。项目不实现 HTTP、SSE、Schema 或工具执行，边界清晰，可被不同 SDK 和 Agent 框架复用。

## 实施与交付
主库及三个适配包已发布 0.1.0；本地 Native 128 项、JS 121 项、wasm-gc 121 项测试及 17 项 Demo 检查通过。交付物包括 Apache-2.0 源码、README、API/语义文档、CI、示例、演示、变更记录和第三方来源说明。后续计划是完成 Gitlink 同步、收集真实接入反馈并持续维护 SDK 兼容性。
