# 设计决策记录

记录与 [项目提案](../../../project-proposal.md) 的偏差及理由。每条决策都说明"为什么不按提案做"。

## D1：`Parser::finish` 返回 `(收尾事件, 结果)`

**提案**：`finish(EndReason) -> CompletedDocument 或 Incomplete/Invalid`。

**实际**：`finish(EndReason) -> (Array[Event], FinishResult)`。

**原因**：一个恰好以数字结尾的文档（如 `[1`），它的 `ValueComplete` 无法在 `feed` 时确认——
后续字节可能把 `1` 变成 `12`。所以最后一个叶值的完成事件只能在 `finish` 时产生。如果 `finish`
只返回结果，消费者会永久丢掉这个事件，预览与最终结果不一致。

这是实现过程中由测试发现的真实缺陷（`chunk_test` 的"末尾数字"用例最初渲染为空）。保留该事件
比让 `feed` 猜测更符合"不猜测尚未到来的内容"的语义。

## D2：词法/语法状态机暂不拆成 `internal/lexer` 与 `internal/syntax`

**提案**：`stream` / `internal/utf8` / `internal/lexer` / `internal/syntax` 四个包。

**实际**：根包公开 API + 同包私有文件（`parser.mbt`、`scanner.mbt`），`internal/utf8` 已删除。

**原因**：

1. 状态机的三个部分共享同一份可变状态（词法子状态、语法栈、UTF-8 待续字节）。跨包拆分需要为
   内部事件再定义一套表示并在 `stream` 中映射回公开 `Event`，双份表示在 M1 阶段只会增加出错面。
2. 错误分类（`Utf8ErrorKind`）若定义在内部包，就会通过公开的 `ParseError::InvalidUtf8` 泄露内部类型；
   在根包重复定义则要靠人工同步。放在根包私有实现里两者都不需要。
3. 从使用者视角，公开 API 与 `.mbti` 完全不受影响——私有文件不出现在接口里。

**何时重做**：当 M2 出现 `preview` / `session` 等第二个公开包、或词法层需要被独立复用时，
再按提案拆分，并在那时定义内部事件表示。

## D3：字符串值在完成前总是先交付 `StringDelta`

**提案**：字符串增量可合并，因此不同分块下事件数组不要求逐项相同。

**实际**：即使字符串在同一个 `feed` 内完整到达，也会先产生一条覆盖完整文本的 `StringDelta`，
再产生 `ValueComplete`。

**原因**：如果不这样做，"整段喂入"与"逐字节喂入"的标准化事件序列会不一致（后者有增量事件，
前者没有），分块不变性就无法作为可测试的不变量。统一先增量后完成，使标准化后的序列在两种
极端分块下逐项相等。

## D4：保留全部原始字节

**提案**：完整树模式需要随文档增长的存储，不宣称总内存恒定。

**实际**：解析器把收到的每个字节都存入 `raw`，`finish` 成功时用它构造 `CompletedDocument` 的文本。

**原因**：`CompletedDocument::to_json` 需要完整文本。代价是内存与输入同阶。若未来需要流式丢弃，
可在 M2 引入"不保留原文"的模式，届时 `to_json` 改由事件流重建。

## D5：`Limits` 字段公开可读，但非法值在构造时拒绝

**提案**：`Parser::new` 对负数或不合法组合拒绝。

**实际**：`Limits::new(...)` 与 `Parser::new(limits=...)` 都做校验并抛出 `InvalidLimits`。
`Limits` 的字段是 `pub(all)`，因此外部可以直接构造——所以 `Parser::new` 必须再校验一次。

**原因**：公开字段便于读取与测试断言；把校验放在唯一的入口（`Parser::new`）保证不会漏。

## D6：V1 严格拒绝重复键

**提案**：V1 严格拒绝，避免先展示一个值后被另一个值覆盖。

**实际**：`DuplicateKey` 在键完成时抛出。

**原因**：与提案一致，无需变更。副作用是"已完成叶值稳定"这条不变量成立的前提得以保证。

## D7：`NumberLiteral` 与 `Json` 的精度策略

**提案**：保留数字原始词法，到 `Json` 的转换是显式操作。

**实际**：事件流中的 `NumberLiteral` 保留原始词法；`CompletedDocument::to_json` 使用核心
`@json.parse`，其 `Json::Number` 携带最短往返表示，因此 `1e3` 会变成 `1000`。

**原因**：核心 `Json` 类型的数值表示不是本项目能控制的。文档与测试都明确写出了这一行为，
需要无损语义的场景请使用事件流里的 `NumberLiteral`。

## D8：适配层拆成独立模块，主库零 SDK 依赖

**提案**：`adapters/*` 作为主模块内的包，"可独立示例模块"。

**实际**：仓库改成 MoonBit workspace（`moon.work`），主库在 `core/`，三个 SDK 适配层是
`adapters/llm_mb`、`adapters/mizchi_llm`、`adapters/moonllm` 三个独立模块。

**原因**：

1. 依赖传染。`moon.mod` 的 `import` 是模块级的：只要适配代码在主模块里，任何
   `moon add trail-it/moonstream` 的消费者都会被拉入 `moonbitlang/async`、`oboard/mio`、
   `bikallem/compress` 等一大串传递依赖——而它们只是解析 JSON。
2. 依赖冲突。`DC-Z-lab/moonllm@0.1.0` 需要 `async@0.20.1`，`marianoguerra/llm@0.2.0+`
   需要 `async@0.21.2`；放在同一个模块里解析器只会取最高版本，导致其中一个编译失败。
   拆成独立模块后每个适配层只承担自己那一个 SDK 的依赖图。
3. 发布边界。`moon -C core package` 产出的归档不再包含适配层源码（这个工具链版本不支持
   `.moonignore` / `include` / `exclude`，因此只能靠目录边界）。

代价是仓库根目录多了一层 `core/`。这是 MoonBit 文档推荐的 workspace 布局。

## D9：SDK 版本按"能编译"固定，并记录工具链约束

**提案**：精确固定已验证的 SDK 版本。

**实际**：

| 适配层 | 固定版本 | 说明 |
|---|---|---|
| `llm_mb_adapter` | `marianoguerra/llm@0.1.1` | 最新版是 0.3.0，但 0.2.0 起要求 `async@0.21.2` |
| `mizchi_llm_adapter` | `mizchi/llm@0.3.1` | 最新版是 0.3.2，它引入了 `async@0.20.5` |
| `moonllm_adapter` | `DC-Z-lab/moonllm@0.1.0` | 该 SDK 只有这一个版本 |

**原因**：本机工具链是 `moon 0.1.20260713` / `moonc 0.10.4`，它无法解析
`async@0.20.5` 与 `0.21.2` 的 native 源码（`async () -> Unit noraise + nocancel`、
`guard!` 等语法）。上述两个固定版本包含当前适配所需的 `StreamEvent` 构造器，只需要
`async@0.20.3`，因此可用。

升级工具链后仍需在兼容任务中验证最新版 SDK；远端 CI 真正运行前，不把“安装最新工具链”
等同于已经验证通过。

## D10：`AdapterOutcome` 放在主库而不是适配层

**提案**：未指定。

**实际**：`trail-it/moonstream/adapter` 包提供 SDK 无关的 `AdapterOutcome`
（`Ignored` / `Updates`）与 `CallUpdate { key, events, result }`。

**原因**：三个适配模块都需要同一个结果类型；放在主库可以避免三份重复定义，也让第三方写自己的
适配层时有统一的结果约定。`CallUpdate` 强制保留调用身份，避免多调用 chunk 的事件失去路由。
它只依赖主库自己的类型，不引入任何 SDK 依赖。

## D11：`Session::open` 用 `String?` 而不是可选参数

**提案**：未指定。

**实际**：`open(self, key, id? : String? = None, name? : String? = None)`。

**原因**：适配层要把 SDK 的 `String?` 字段（`ToolCallDelta.id` / `.name`）直接透传。
若用可选参数（`id? : String`），调用点只能写 `id=value` 或省略，无法传递一个已经是 Option 的值，
每个适配层都要写四分支的 `match` 拆包。

## D12：`mizchi/llm` 适配层用 id→序号映射

**提案**：未指定。

**实际**：`mizchi/llm` 用字符串 `id` 标识工具调用，而 `CallKey.index` 是整数。适配层按 id 首次
出现的顺序分配序号，`slot(id)` 公开这个映射。

**原因**：保持 `CallKey` 的字段类型稳定，不让某个 SDK 的标识形式渗进核心类型。映射是确定性的，
并且 `ToolCallEnd` 携带的 `input : Json` 可以直接用来对照本库产出的文档（测试里就这么做）。

## D13：演示模块用链接配置 `exports`，不用 `#export_name`

**提案**：`examples/browser` 用少量宿主胶水接入 wasm-gc 页面。

**实际**：`demo/wasm/moon.pkg` 用

```text
options(
  "link": {
    "wasm-gc": {
      "exports": [ "demo_step:moonstream_demo_step", ... ],
    },
  },
)
```

而不是 `#export_name` + `pkgtype(kind: "foreign_library")`。

**原因**：`#export_name` 要求包声明为 `foreign_library`，但这类包在 `moon test` 下会尝试构建
测试产物并报错（`#export_name` 在测试产物里不合法），而 native 后端也不支持把 `foreign_library`
导出成可链接产物。用链接配置的 `exports` 得到的 wasm-gc 产物导出集完全一样（已验证：
6 个导出、0 个导入），同时包仍是普通库包，三后端都能正常检查与测试。

## D14：性能报告只公布实测与比值，不做内存断言

**提案**：记录扫描工作量、事件数、分配与耗时，公布机器/运行时/编译器信息，不预写性能提升数字。

**实际**：[docs/performance.md](performance.md) 给出输入规模、分块大小、预览投影、多调用路由的
实测表格，并与核心 `@json.parse` 同场对照；内存只给结构性事实（`raw` 保留全部输入、
`CompletedDocument::byte_length`、`Preview::node_count`），不声称分配统计。

**原因**：MoonBit 没有暴露稳定的分配计数器，`@bench` 也不测量内存；声称"内存降低 N%"无法复现。
另外这台机器噪声很大（同一基准相邻两次运行均值可差 2 倍），所以报告同时给出 mean 与 min，
并把**比值**（同一次运行内）作为主要判据。

## D15：干净环境复现用脚本固化

**提案**：干净环境可复现；真实安装已发布版本。

**实际**：`scripts/verify-clean.mjs` 把仓库复制到临时目录（排除 `_build`、`.mooncakes`、`.git`），
在副本里跑 `moon check --deny-warn --target all`、三后端测试、演示构建与端到端检查、主库打包。

**原因**：把"可复现"变成一条可执行的命令，而不是文档里的承诺。**尚未**完成的部分是
"从注册表安装已发布版本"——那需要先发布到 mooncakes.io。
