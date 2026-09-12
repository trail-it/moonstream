# MoonStream 项目申报摘要（待补仓库链接）

- 项目名称：MoonStream。
- GitHub 仓库：https://github.com/trail-it/moonstream。
- Gitlink 仓库：待创建并与 GitHub 同步。
- 项目类型：原创增量解析库；基于现有 SDK 的公开类型实现接入，非跨语言代码移植。
- 一句话：为 MoonBit 提供 LLM 流式结构化输出的字段事件与完整性判断能力。
- 方向与场景：基础组件；工单草稿、结构化表单及多个工具调用的实时预览。
- 生态价值：SDK 提供文本片段，MoonStream 补充半成品 JSON 的严格增量语义与调用隔离。
- 核心功能：字节状态机、跨块 UTF-8、字段事件、Preview、Session、三种 SDK 适配。
- 完整性：内容块结束不等于响应正常结束；截断与取消不能产生 CompletedDocument。
- 独立贡献：原创解析状态机、分块不变性约定、调用键路由和可测试的结束契约。
- 实施进展：本地实现与回归已完成；公开发布、远端 CI 和外部使用验证待完成。
- 交付物：Mooncakes 主库及独立适配包、API 文档、消费者示例、CLI 回放、wasm-gc 演示。
- 验证：native / JS / wasm-gc 测试及部署 wasm 自动检查；详见验收报告。
- 计划：补真实仓库与开发记录 → 远端 CI → 发布 → 从注册表安装验证 → 获取使用反馈。
- 许可证：Apache-2.0；SDK 与生成文件的来源说明见 THIRD_PARTY.md。
- 范围边界：不实现模型网络协议、SSE、Schema、任意 JSON 修复或自动工具执行。
- 参赛资格与当前时间窗口：以赛事组确认结果为准，本文件不表示已报名或已获验收。
