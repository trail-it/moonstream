# 来源与依赖说明

本项目按设计文档实现 MoonBit 增量解析状态机，没有把某个其他语言的 parser 整体移植进来。
这一说明依据本地设计材料和当前实现；仓库尚无可追溯提交历史，作者仍应在提交前确认全部来源。

| 直接 SDK 依赖 | 固定版本 | 上游许可证 | 使用范围 |
|---|---|---|---|
| [marianoguerra/llm](https://github.com/marianoguerra/llm-mb) | 0.1.1 | Apache-2.0 | llm_mb 适配器使用公开 StreamEvent |
| [mizchi/llm](https://github.com/mizchi/llm) | 0.3.1 | MIT | mizchi_llm 适配器使用公开 StreamEvent |
| [DC-Z-lab/moonllm](https://github.com/DC-Z-lab/moonllm) | 0.1.0 | Apache-2.0 | moonllm 适配器使用 StreamChunk / ToolCallDelta |

许可证信息来自本地下载版本的模块 manifest。SDK 通过包管理器解析，没有把 .mooncakes 缓存
作为本项目源码发布。传递依赖保留各自上游许可证；本项目 Apache-2.0 不替代依赖许可证。
主库使用 MoonBit 标准库，不依赖上述 SDK。

pkg.generated.mbti 是 moon info 生成的接口摘要；_build 和 demo/www/moonstream_demo.wasm
为构建产物。AI 辅助过设计、实现、测试及文档修订，编译器生成文件与 AI 辅助源码应区分。
当前测试与演示使用仓库内的合成 JSON、算法生成样本及 SDK 类型构造的事件，没有真实用户
会话或在线模型返回记录。后续若加入外部 fixture、复制代码或数据集，应在此列明来源与授权。
