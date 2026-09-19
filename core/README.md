# MoonStream

> 为 MoonBit 生态提供 **LLM 流式结构化输出的字段级增量解析与完整性契约**。

模型逐块吐出的 tool-call 参数是「永远还没写完的 JSON」。MoonStream 消费已经提取出来的参数片段字节，
跨片段保存语法状态，交付**结构事件**、**已完成叶值**和**完整性判断**——不负责连接模型，也不假装
预览就是最终结果。

版本：**0.1.1**。[GitHub 仓库](https://github.com/trail-it/moonstream)。

## 它解决什么问题

已有 SDK（`mizchi/llm`、`DC-Z-lab/moonllm`、`marianoguerra/llm-mb` 等）把工具参数作为文本增量交付，
或者要求消费者等到流结束再解析。于是每个应用都要自己处理半个字符串、半个数字、未闭合对象、跨块
UTF-8 码元和被截断的流。

MoonStream 把这一层做成可复用的独立能力：

- **逐字段可用**：键名和已闭合的叶值在流未结束时就以事件形式交付。
- **不猜测**：`{"count":1` 不会被当成数字 `1` 交付，因为后面还可能是 `2`、`.5` 或 `e2`。
- **明确的交付边界**：只有 `finish(EndOfStream)` 返回的 `CompletedDocument` 才代表整篇文档合法。
- **分块无关**：同一输入的任何切分方式，最终文档与标准化事件序列都一致。

## 快速开始

```bash
# 在仓库根目录运行本地示例
moon run --target native examples/consumer
# 在你的项目中安装：moon add trail-it/moonstream
```

```mbt check
///|
test {
  let parser = Parser::new()
  // 逐块喂入已经提取出来的参数片段字节
  let first = parser.feed(b"{\"city\":\"上")
  inspect(first.length(), content="3")
  let second = parser.feed(b"海\",\"count\":12}")
  inspect(second.length(), content="5")
  // 只有正常结束才可能得到可交付的文档
  let (_, result) = parser.finish()
  match result {
    FinishResult::Completed(doc) =>
      inspect(doc.to_string(), content="{\"city\":\"上海\",\"count\":12}")
    _ => fail("应当完成")
  }
}
```

事件流形如：

```text
ObjectBegin  $
KeyComplete  $.city
StringDelta  $.city = 上
StringDelta  $.city = 海
ValueComplete $.city = "上海"
KeyComplete  $.count
ValueComplete $.count = 12
ObjectEnd    $
```

## 核心概念

| 类型 | 含义 |
|---|---|
| `Parser` | 单个 JSON 文档的增量解析器；`feed(Bytes)` 或 `feed_text(StringView)` 消费片段，`finish(EndReason)` 判定完整性 |
| `Event` | 结构事件：容器开始/结束、键完成、字符串增量、叶值完成 |
| `Path` | 文档内位置，如 `$.items[0].name`；只描述位置，不承诺值合法 |
| `Span` | 绝对字节区间；与分块方式无关 |
| `NumberLiteral` | 保留原始词法的数字，避免大整数被静默舍入 |
| `CompletedDocument` | 不透明类型，只有解析器能构造；代表整篇文档在严格语法策略下合法 |
| `Limits` | 深度 / 单 token 字节 / 节点数 / 总输入四个上限 |

`preview` 与 `session` 两个包建立在同一套事件之上：

| 类型 | 含义 |
|---|---|
| `@preview.Preview` | 批量投影事件并枚举已完成叶值，供 UI 逐帧渲染；不能构造 `CompletedDocument` |
| `@preview.NodeState` | 某路径的状态：`Missing` / `Pending` / `Container(kind, closed)` / `IncompleteString(text)` / `Complete(value)` |
| `@session.Session` | 多 tool call 会话：按 `(response, choice, index)` 复合键把片段路由到独立解析器 |
| `@session.CallKey` | 稳定复合键；同一键对应且只对应一个 JSON 文档 |
| `@adapter.CallUpdate` | 单个调用的一次更新：稳定 `CallKey`、事件和可选结束结果 |
| `@adapter.AdapterOutcome` | SDK 适配层处理一个事件后的结果：`Ignored` / `Updates(Array[CallUpdate])` |

### 部分树预览

```mbt check
///|
test {
  let parser = Parser::new()
  let preview = @preview.Preview::new()
  for event in parser.feed(b"{\"city\":\"上") {
    preview.apply(event)
  }
  // 字符串正在增长，不是最终值
  inspect(
    preview.to_preview_string(),
    content="{\"city\":\"上…,…}",
  )
  inspect(
    preview.lookup(Path::root().child_key("city")) is @preview.NodeState::IncompleteString(..),
    content="true",
  )
}
```

### 多调用路由

```mbt check
///|
test {
  let session = @session.Session::new()
  let first = @session.CallKey::new(response="resp-1", choice=0, index=0)
  let second = @session.CallKey::new(response="resp-1", choice=0, index=1)
  session.open(first, id=Some("call_a"), name=Some("create_ticket"))
  session.open(second, id=Some("call_b"), name=Some("send_mail"))
  // 片段交错到达
  let _ = session.feed(first, b"{\"title\":\"登")
  let _ = session.feed(second, b"{\"to\":\"a@b.c\"}")
  let _ = session.feed(first, b"录失败\"}")
  let (_, first_result) = session.finish(first)
  let (_, second_result) = session.finish(second)
  inspect(
    match first_result {
      FinishResult::Completed(doc) => doc.to_string()
      _ => "?"
    },
    content="{\"title\":\"登录失败\"}",
  )
  inspect(
    match second_result {
      FinishResult::Completed(doc) => doc.to_string()
      _ => "?"
    },
    content="{\"to\":\"a@b.c\"}",
  )
}
```


## 语义保证

保证（有测试覆盖）：

- 在严格无重复键策略下，被语法边界确认完成的叶值，若最终文档合法，则不会再被后续合法输入改变。
- 任意分块方式得到同一最终文档、同一错误位置，以及**标准化后**等价的事件序列。
- 字符串增量合并后恰好覆盖该字符串的完整文本。
- 只有 `EndOfStream` 能产生 `CompletedDocument`；取消与截断返回 `Aborted`。

不保证：

- 不保证所有预览节点单调不变（字符串仍在增长、数字仍可能变长）。
- 不保证已完成子树等于整篇文档合法。
- 不做任意损坏 JSON 的修复；解析器不会"补右括号"再交付。
- 不防止 prompt injection、恶意参数或所有资源耗尽攻击。

细节见 [docs/semantics.md](docs/semantics.md)。

## 与 RFC 8259 的差别

MoonStream 采用 RFC 8259 的 JSON 语法，并在以下位置**更严格**（均为显式策略）：

- 重复键：V1 直接拒绝（`DuplicateKey`），避免先展示的值被后出现的值覆盖。
- 字符串中的孤立代理项：拒绝（`InvalidUnicodeEscape`），包括高位代理后不接低位代理的情况。
- UTF-8：严格校验，拒绝过度长编码、代理项码位和超出 U+10FFFF 的序列。
- 根值之后只允许空白：出现其它内容即 `TrailingContent`。

标准本身不定义"部分 JSON"，因此增量状态与完成契约是本项目公开规范的一部分。

## 资源限制

`Limits::new` 可配置四个上限，触发时抛出带位置与限制类型的 `LimitExceeded`：

```mbt check
///|
test {
  let limits = Limits::new(max_depth=3)
  let parser = Parser::new(limits=limits)
  let failed = try {
    let _ = parser.feed(b"[[[[1]]]]")
    false
  } catch {
    ParseError::LimitExceeded(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(failed, content="true")
}
```

## 离线回放工具

`cmd/replay` 把一段文本按固定字节大小分块喂入，打印事件与最终判断，用于复现和演示：

```bash
moon run --target native cmd/replay                 # 内置样本
moon run --target native cmd/replay -- '[1,2' 2     # 截断场景
moon run --target native cmd/replay -- '01' 1       # 前导零错误
```

## 测试与多后端

在仓库根目录（workspace 上下文）执行：

```bash
moon check --deny-warn --target all
moon test --target wasm-gc              # 124 个测试
moon test --target js                   # 124 个测试
moon test --target native               # 131 个测试（含 native-only 的 moonllm 适配）
moon fmt && moon info
moon -C core package                    # 主库发布包
```

测试覆盖：完整语法、跨块切分不变性（穷举单切点 + 固定 seed 多段 + 逐字节）、前缀行为对照独立
oracle、负面控制、Unicode 与代理对、数字词法与精度、资源限制边界、解析器生命周期、
部分树状态区分、多调用交错与冲突检测，以及用真实 SDK 类型驱动的三个适配层。

## 目录结构

```text
moonstream/
├── moon.mod / moon.pkg
├── parser.mbt        # 公开 API、语法上下文、主循环、finish
├── scanner.mbt       # 词法与语法状态机的单步转移
├── event.mbt         # Event / LeafValue / NumberLiteral
├── path.mbt          # Path / PathSegment
├── span.mbt          # Span
├── limits.mbt        # Limits
├── error.mbt         # ParseError / Utf8ErrorKind / LimitKind
├── document.mbt      # CompletedDocument / EndReason / FinishResult
├── preview/          # 部分树投影（NodeState / Preview）
├── session/          # 多 tool call 路由（CallKey / Session）
├── adapter/          # SDK 无关的适配层支持类型（CallUpdate / AdapterOutcome）
├── *_test.mbt        # 黑盒测试与测试工具
├── tests/            # 消费者视角的跨包集成测试
├── cmd/replay/       # 离线回放工具（native）
└── docs/             # 语义规范与设计决策
```

真实 SDK 的适配层在仓库的 [`adapters/`](../adapters/) 下，各自是独立模块
（`trail-it/llm_mb_adapter`、`trail-it/mizchi_llm_adapter`、`trail-it/moonllm_adapter`），
因此主库不依赖任何 LLM SDK。

## 与相邻项目的关系

| 项目 | 它做什么 | 本项目的位置 |
|---|---|---|
| `mizchi/llm`、`DC-Z-lab/moonllm`、`marianoguerra/llm-mb` | 模型协议、SSE、参数文本增量 | MoonStream 消费它们已经提取出的参数片段；仓库内已有三者的适配层 |
| `moonbitlang/jsonl` | 按行读取完整 JSON 记录 | 处理的是单个尚未结束的文档 |
| `oboard/jsonx` | 已解析 `Json` 的读取与派生 | 不重新实现 Json 包装 |
| `Betterlol/moon_zod`、`cosgammmmmmmma/moonschema` | 对已形成的数据做结构与约束校验 | 解析完成后接入它们，不重写校验层 |

## 路线图

- **M1（已完成）**：字节增量词法与语法状态机、完整性模型、分块不变性测试、回放工具。
- **M2（已完成）**：`Preview` 部分树投影、`Session` 多 tool call 路由、三个真实 SDK 适配层。
- **M3（已完成）**：浏览器 wasm-gc 离线演示、复杂度回归基线、适配层编写指南、干净环境复现脚本。
- **M4**：生态反馈、API 收敛、维护计划。

## 相关文档

- [docs/semantics.md](docs/semantics.md) —— 语义规范（规范性文本）
- [docs/performance.md](docs/performance.md) —— 复杂度与性能基线（实测）
- [docs/adapters.md](docs/adapters.md) —— 写第三方 SDK 适配层
- [docs/review-2026-09.md](docs/review-2026-09.md) —— 独立审查记录与缺陷修复
- [docs/design-decisions.md](docs/design-decisions.md) —— 设计决策与偏差记录
- [`../demo/`](../demo/) —— 浏览器 wasm-gc 离线演示
- [`../scripts/verify-clean.mjs`](../scripts/verify-clean.mjs) —— 干净环境复现

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。
