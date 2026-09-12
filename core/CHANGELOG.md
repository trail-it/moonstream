# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的结构，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [0.1.1] - 2026-09-12

- 使用新旧工具链均支持的 StringBuilder 构造和 Debug trait 格式化。
- 同步 feed 的失败终态保持契约；成功后才重新开放解析器。
- 修复首次 CI 缺少注册表索引更新的问题。

## [0.1.0] - 2026-09-12

- 首次以 trail-it 命名空间发布主库与三个独立 SDK 适配器。

### Fixed — 2026-09-12 acceptance

- 批量收尾通过 CallUpdate.failure 逐调用报告错误，保留其它调用的完成结果与事件。
- 演示截断后保留实际进度，重复截断与终态步进不再损坏状态。
- 演示检查默认读取页面实际部署的 wasm，增加终态与进度回归。
- 消费者样例实际切开 UTF-8 字符；同步文档、来源说明与申报摘要。

### Fixed — integration contract review

- SDK 适配器现在等待响应级终止原因，长度截断、错误与取消不再被提前交付为 `Completed`。
- `AdapterOutcome` 返回带 `CallKey` 的 `CallUpdate`，同一 chunk 的多个工具调用可可靠路由。
- `moonllm` 批量收尾保留末尾数字产生的 `ValueComplete` 事件。
- 解析失败的 Session 调用进入可查询的 `Failed` 状态，不再阻断其它调用的批量收尾。
- 总输入上限报告第一个超限字节，错误位置及优先级不再依赖输入分块。

### Added — M1 核心

- 字节增量词法状态机：字符串（含转义、`\uXXXX`、代理对）、数字、`true`/`false`/`null`，
  全部支持在任意字节边界处中断与续读。
- 显式语法栈：对象/数组的键、冒号、逗号与结束状态，根值之后的尾随内容检查。
- 跨块 UTF-8 解码：缓存不完整码元序列，拒绝孤立续字节、过度长编码、代理项码位与超出 U+10FFFF 的序列。
- 完整性类型模型：`CompletedDocument` 只能由 `Parser::finish(EndOfStream)` 产生；
  `Incomplete` 与 `Aborted` 显式区分"还没写完"和"不是正常结束"。
- 结构事件：`ObjectBegin` / `ObjectEnd` / `ArrayBegin` / `ArrayEnd` / `KeyComplete` /
  `StringDelta` / `ValueComplete`，均携带 `Path` 与 `Span`。
- 数字保留原始词法（`NumberLiteral`），并提供显式的 `to_double` 有损转换。
- 资源限制：`max_depth`、`max_token_bytes`、`max_nodes`、`max_total_bytes`。
- 严格策略：重复键拒绝、孤立代理项拒绝、未转义控制字符拒绝。
- `cmd/replay` 离线回放工具（native），可复现分块解析过程。
- 测试：分块不变性（穷举单切点、固定 seed 多段、逐字节）、前缀行为对照独立 oracle、
  负面控制、Unicode、数字、限制边界、生命周期，共 65 个测试，在 wasm-gc / js / native 三后端通过。
  核心库未覆盖行仅剩不可达的防御性分支；`cmd/replay` 的未覆盖行由 CI 的实际运行覆盖。

### Added — M2 可复用集成

- `trail-it/moonstream/preview`：把事件投影成部分树。`NodeState` 显式区分
  `Missing` / `Pending` / `Container(kind, closed)` / `IncompleteString(text)` / `Complete(value)`，
  其中 `Complete(LeafValue::Null)` 与 `Missing` 严格分开。没有把部分树转成 `CompletedDocument`
  的公开构造器；`to_preview_string()` 用 `…` 标出未完成部分。
- `trail-it/moonstream/session`：多 tool call 路由。`CallKey{response, choice, index}` 复合键，
  每个键对应独立 `Parser`；未 `open` 就 `feed` 抛 `UnknownCall`，id / 函数名冲突抛
  `CallIdConflict` / `CallNameConflict`，单调用失败包装成 `ParseFailed` 且不影响其它调用。
- `trail-it/moonstream/adapter`：SDK 无关的 `AdapterOutcome`（`Ignored` / `Delta` / `Finished`）。
- 仓库改为 MoonBit workspace：主库在 `core/`，三个 SDK 适配层是独立模块
  `trail-it/llm_mb_adapter`、`trail-it/mizchi_llm_adapter`、`trail-it/moonllm_adapter`。
  主库因此保持**零 SDK 依赖**，`moon -C core package` 的归档不包含适配层。
- 适配层测试全部用 SDK 的真实类型驱动：`marianoguerra/llm` 的 `StreamEvent`、
  `mizchi/llm` 的 `StreamEvent`（并用其 `ToolCallEnd.input : Json` 对照本库结果）、
  `DC-Z-lab/moonllm` 的 `StreamChunk` / `ToolCallDelta`。

### Added — M3 质量与发布

- `demo/`：浏览器 wasm-gc 离线演示。MoonBit 把「同一段参数流在 MoonStream 下的逐字段演进」
  算成一份 JSON 状态，宿主页面只负责绘制；产物是**零导入**的 wasm-gc 模块。
  `demo/check.mjs` 用 Node 加载真实产物跑完整流程（浏览器与 Node 共用同一份 `host.js`）。
- `core/perf/` 与 [docs/performance.md](docs/performance.md)：复杂度与回归基线。
  记录扫描成本随输入规模（393 B → 223 KiB）、分块大小（1 B → 4 KiB）、预览投影与多调用路由的
  实测数字，并与核心 `@json.parse` 同场对照；同时公布机器与工具链信息。
- [docs/adapters.md](docs/adapters.md)：写第三方 SDK 适配层的指南（键映射、边界、测试写法）。
- `scripts/verify-clean.mjs`：把仓库复制到临时目录（无 `_build` / `.mooncakes`）后跑
  检查、三后端测试、演示构建与端到端检查、主库打包，证明结果不依赖本地构建状态。
- 解析器内部缓存了「键对应的值路径」，避免每个值重复构造一次 `Path`。

### Added — M4 API 收敛与维护材料

- `Parser::is_finished()`、`Session::calls()`（返回全部已注册调用键，含已结束的）。
- `Preview::children(path)`：枚举容器的直接子节点，UI 可渲染"键名还不知道"的对象。
- `FinishResult` / `CompletedDocument` / `AdapterOutcome` 现在都实现 `Eq` 与 `ToJson`。
- `MAINTAINING.md`：项目边界、兼容性基线、什么算破坏性变更、发布 checklist、工具链升级流程、
  依赖策略、缺陷处理。
- [docs/demo-script.md](docs/demo-script.md)：三分钟演示脚本（含常见提问准备与"不要声称"清单）。
- [docs/outreach.md](docs/outreach.md)：候选接触对象与消息草稿（**一份都没发出**）。

### Fixed — 独立审查发现的问题

一轮对抗性审查（见 `core/docs/review-2026-09.md`）确认了以下缺陷，全部已修并补了回归测试：

- **字符串内未收齐的 UTF-8 序列会被闭合引号或反斜杠吞掉**：`["<E4>","x"]` 曾产出
  `ValueComplete($[0], String(""))`，错误被推迟到 `finish` 且位置变成 0。现在在待续状态下
  遇到非续字节立刻抛 `InvalidUtf8(起点位置)`。
- **`Preview` 的根节点是占位对象**：导致根值为字符串的文档无法投影（`PathConflict`）、
  根值标量时 `node_count()` 为 0、空预览的 `lookup(根路径)` 返回容器。现在根节点是 `Node?`，
  空预览的根路径是 `Missing`，计数与渲染一致。
- **`StringDelta` 的区间在分块边界上不一致**：整段解析得到 `[5,9]`、分块解析得到 `[5,8]`。
  增量事件的区间现在统一不含闭合引号；测试辅助函数 `render_event` 也把 `span` 纳入渲染，
  使分块不变性真正覆盖区间。
- **非法数字的错误种类不稳定**：`{"a":1..2}` 报 `InvalidNumber`，而 `{"a":1.2.3}` 报
  `TrailingContent`。现在凡是数字内部字符（`.`/`e`/`E`/数字）导致的失败一律 `InvalidNumber`。
- **`Session::new` 的错误通道与其它 API 不一致**：它抛 `ParseError`，其余抛 `SessionError`。
  现在包装为 `SessionError::InvalidLimits`；三个适配层的构造函数同步改抛 `SessionError`。
- `CompletedDocument::byte_length()` 之前返回 UTF-16 码元数，现在返回**真实字节数**。
- `CompletedDocument::to_json` 的错误类型从任意 `raise` 收窄为 `@json.ParseError`。
- `NumberLiteral::to_double` 的文档与实际行为不符：上溢返回 `None`、下溢按 IEEE 754 归零
  （返回 `Some(0.0)`）。文档已改正，并补了对应测试。

### Changed — 文档修正

- `Preview` 的状态表注明 `Pending` 只出现在对象成员上；数组元素在完成前是 `Missing`。
- 空预览的根路径是 `Missing`，`children()` 的行为也写进 `semantics.md` §12。
- 三个不透明类型的 docstring 不再声称"内部状态不会出现在 `.mbti`"——实际会显示一个
  不透明字段名；改的是它的**内部字段**不影响公开接口，改类型名才会。
- 修正 `adapters/*` 目录名笔误。

### Changed — API 收敛

- `Parser` / `Preview` / `Session` 的内部状态收进私有类型（`ParserState` / `PreviewState` /
  `SessionState`），`.mbti` 里每个类型只剩一个不透明字段：内部字段重构不再表现为公开接口变化。
- `Session::open` 的两个元数据参数改为带默认值的标签参数
  （`open(key, id=..., name=...)`），既保留直接透传 SDK `String?` 字段的能力，
  又让调用点可读、可只给其中一个。

### Changed — 与设计提案的偏差

- `Parser::finish` 返回 `(收尾事件, 结果)` 而不是只返回结果：恰好以数字结尾的文档，
  它的 `ValueComplete` 只有在 `finish` 时才可确认，收尾事件必须一并交付。
- 词法与语法状态机目前实现于根包内的私有文件，未拆分为 `internal/lexer` 与 `internal/syntax`
  两个包。原因见 [docs/design-decisions.md](docs/design-decisions.md)。
- 适配层不在主模块内，而是 workspace 成员；SDK 版本按"本机工具链能编译"固定
  （`llm@0.1.1`、`mizchi/llm@0.3.1`），接口与各自最新版一致。理由见设计决策 D8/D9。
- 演示模块用 `moon.pkg` 的链接配置 `exports` 而不是 `#export_name`，因为后者要求
  `foreign_library` 包，而该包在 `moon test` 下无法构建测试产物。见设计决策 D13。

### Not yet

- 未发布到 mooncakes.io，未创建 GitHub / Gitlink 仓库。
- 未在注册表安装"已发布版本"做端到端验证（需要先发布）。
