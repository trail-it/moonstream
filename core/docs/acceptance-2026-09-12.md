# MoonStream 本地验收报告

日期：2026-09-12。范围：moonstream 工作区。依据：osc2026-guide 的 Review Mode、附带的
2026-05-11 版章程及 supplemental-knowledge；代码修订遵循 moonbit-agent-guide 和 core/AGENTS.md。
本次为本地检查及修复，不代表赛事组正式验收。

## 总体判断

本轮执行的本地检查通过，发现的演示、样例和批量收尾缺陷已修复。赛事提交条件尚未齐备：
GitHub / Gitlink 公开仓库、有效开发历史、Mooncakes 发布与注册表安装验证仍缺少证据。
本地可构建归档不等于已经发布。

项目是以 MoonBit 为主的可复用库，包含严格字节解析、字段事件、部分树、多调用路由及真实 SDK
类型适配；不是模板空壳。已有生态研究指出与 SDK 文本增量、jsonl、Json 包装及 Schema 工具的
差异，本轮沿用该研究和本地源码证据，没有重新穷尽搜索 9 月 12 日的整个生态。

## 本轮发现与修复

| 问题 | 修复 | 验证 |
|---|---|---|
| 中间调用在 finish 才失败，批量收尾会丢失已完成结果并跳过后续调用 | 公共 finish_open 逐调用捕获错误，CallUpdate.failure 保留失败，结果和收尾事件继续返回 | 三调用回归：成功数字、未收齐 UTF-8、成功数字 |
| 模拟截断把进度强行设为 100% | 保留实际 step / offset；终态步进与重复截断为无操作 | 部署 wasm 检查确认 2/17 保留、不会继续消费 |
| 完成后点击截断会把正常结果改成错误 | 已结束状态直接返回 | 部署 wasm 检查 |
| 自动检查读取构建缓存，无法证明页面产物正确 | 默认读取 demo/www/moonstream_demo.wasm，缺失时要求运行 build.mjs | 实际加载部署文件并完成 17 项检查 |
| 样例声称切开 UTF-8，实际传完整汉字 | 第二块只传 E4，第三块补 B8 8A | 消费者输出前两块 Pending，最终上海与 28 字节文档 |
| 适配指南存在不存在的 SDK 骨架、错误参数和陈旧契约 | 改为实际版本、真实结束信号、错误处理与迁移说明 | 核对实现及生成的 mbti |
| README 安装步骤在未发布状态不可用、英文示例误导 finish 后继续等待 | 提供当前可运行本地示例；解释 Incomplete 也终止解析器 | 实际运行 examples/consumer |
| 验收材料版本要求、测试数量和进度陈旧 | 同步 README、ACCEPTANCE、状态文档；CI 固定 Node 24 并显式构建所有支持后端 | 本地命令与 CI 配置核对 |

API 变化：CallUpdate 新增 failure；@adapter.finish_open 是共享批量结束入口；MoonllmAdapter::finish_all
现在返回每调用的更新而不抛出批量结束错误。单次 apply 的输入或元数据错误仍通过 SessionError
抛出。客户端必须处理 update.failure，并且只交付 Completed。本项目未发布，此次变化仍需在
首次发布说明中明确记录。

## 已检查的证据

| 检查 | 结果 |
|---|---|
| moon version --all | moon 0.1.20260713；moonc v0.10.4+2cc641edf；moonrun 0.1.20260713 |
| Node | v24.19.0 |
| moon check --target all --deny-warn | 通过 |
| moon test --target native | 128 passed，0 failed |
| moon test --target js | 121 passed，0 failed |
| moon test --target wasm-gc | 121 passed，0 failed |
| moon build --target all | 通过，按包的 supported_targets 构建 |
| moon info / moon fmt | 通过；已检查 CallUpdate、finish_open、finish_all 的生成接口变化 |
| moon run --target native examples/consumer | 正确输出上海、12、28 字节可交付文档 |
| moon -C core run --target native cmd/replay | 内置样本 Completed，134 字节 |
| node demo/build.mjs / node demo/check.mjs | 构建成功；17 项通过 |
| 四个模块的 moon package | 全部成功；均提示 repository 尚空 |
| 归档检查 | 四个包各含 LICENSE，均不含 .mooncakes 依赖缓存 |
| 根目录及模块许可证 | Apache-2.0 文件存在；THIRD_PARTY.md 列明三个 SDK 的版本、许可证和使用范围 |
| Git | 仓库已初始化，无 HEAD、无提交和 remote；以进程级 safe.directory 读取，未改全局设置 |

源码规模估计：37 个 .mbt 文件，剔除空行和独立注释行后，实现约 2,513 行，测试约 2,416 行；
不计 .mooncakes、_build 和生成 mbti。这个口径包括结构括号行，不等同于赛方有效工作量。
章程的 4–10k 为项目规模参考，不能据此单独判定通过或失败，更不应为凑行数增加无用代码。

## 提交前需要处理的问题

1. **开发记录高风险**：当前为 0 个提交，符合技能的“不超过 10 个提交为高风险”条件。
   应保留后续真实、有意义的开发提交；不能补造时间、空提交或按文件拆分凑数。
   因无历史，不能核算 2026-04-29 之后的有效增量工作。
2. **仓库与镜像**：需要实际 GitHub 和 Gitlink 链接、默认分支上的完整源码及同步记录。
   当前没有 remote，无法验证默认分支或公开可访问性。未编造链接写入 repository。
3. **发布**：包命名空间为 Magic486，已替换模板 username，但是否属于参赛者账号需要本人确认。
   填写真实 repository 后发布，再从注册表安装到独立消费者项目；当前打包在 workspace 内验证。
4. **申报材料**：原 project-proposal.md 为 249 行设计文档，超过技能建议的 Markdown 30 行。
   已另备少于 30 行的 SUBMISSION.md，保留原设计文档。摘要仍须填写真实仓库链接才能提交。

## 需要进一步确认的问题

- 当前日期晚于技能附带章程所列 7 月验收和 8 月展示时间。是否存在延期、补交或另一届活动，
  需向赛事组确认；本报告没有查询在线章程，也不认定当前仍可报名。
- CI 配置覆盖 check/build/test，但尚无远端运行记录；不能以本机通过推断 Ubuntu 最新工具链通过。
- 代码来源说明基于当前源码与对话中的设计过程。没有提交历史，无法独立证明全部历史来源；
  作者须核对 AI 辅助源码、上游引用和合成样例，后续加入外部数据需补来源说明。
- 本轮没有调用真实模型服务、联系维护者、验证外部采用、重跑性能基准或无缓存联网复现脚本。
  前一轮浏览器交互记录可供参考，本轮演示修复通过共享宿主和实际部署 wasm 验证，未重跑浏览器 UI。

## 可选环境建议

本地已安装 moonbit-agent-guide，MoonBit 开发技能可用。当前 moonc 为 0.10.4，低于技能提到的
1.0 环境建议；建议单独安排工具链升级和 SDK 兼容验证，再更新性能基线。本轮未修改全局工具链。
