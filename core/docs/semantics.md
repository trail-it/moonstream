# MoonStream 语义规范（V1）

本文是 MoonStream 增量解析的**规范**：它定义什么是"一个字段已经完成"、什么时候文档可以交付、
以及不同分块方式之间必须保持一致的东西。实现必须与本文一致；本文未承诺的内容，实现不做保证。

## 1. 范围与基线

- 语法基线：RFC 8259 的 JSON 语法。
- 本规范额外定义的部分：**增量状态**、**完成事件**与**完整性判定**。RFC 8259 只描述完整文档，
  不定义"部分 JSON"，因此这一层属于本项目公开契约。
- 不在范围内：模型协议、SSE 分帧、JSON Schema 校验、任意损坏 JSON 的修复、工具执行。

## 2. 输入模型

- 输入是**字节**（UTF-8），不是 `String`，也不是网络帧。调用方负责从 SDK 的文本增量中提取参数片段
  并编码为字节。
- 偏移以"本次解析会话收到的全部字节"为基准，从 0 开始，按字节计。偏移与分块方式无关。
- 空输入块不改变解析状态，也不产生事件。

## 3. 语法上下文

解析器维护一个显式容器栈。当前上下文决定下一个非空白字节必须是什么：

| 上下文 | 允许的字节 |
|---|---|
| 文档开始 | 一个值的开始 |
| 文档结束 | 仅空白 |
| 对象：键或结束 | `"` 或 `}` |
| 对象：键（`,` 之后） | `"` |
| 对象：冒号 | `:` |
| 对象：值 | 一个值的开始 |
| 对象：逗号或结束 | `,` 或 `}` |
| 数组：值或结束 | 一个值的开始或 `]` |
| 数组：值（`,` 之后） | 一个值的开始 |
| 数组：逗号或结束 | `,` 或 `]` |

空白为 U+0020、U+0009、U+000A、U+000D，可在任何词法边界之间出现。

## 4. 词法状态

每个 token 内部状态跨 `feed` 调用保存：

- **字符串**：普通字符 / 反斜杠之后 / `\uXXXX` 已读 0–3 位 / 等待代理对的 `\`、`u`、低位十六进制。
- **数字**：符号 / 前导零 / 整数 / 小数点 / 小数 / 指数标记 / 指数符号 / 指数数字。
- **字面量**：`true` / `false` / `null` 的逐字匹配进度。
- **UTF-8**：字符串内部的多字节序列可跨任意字节边界；未收齐时缓存，收齐后一次性交付该码点。

## 5. 完成规则

"完成"指**语法边界已经确认该值不可能再被后续合法输入改变**。不同 token 的确认时机不同：

| token | 完成时机 | 说明 |
|---|---|---|
| 字符串（值） | 读到闭合引号 | 闭合引号之后不可能再延长该字符串 |
| 数字 | 读到非数字字符（空白、`,`、`}`、`]`）或 `finish` | `{"count":1` 不能提前完成，后面还可能是 `2`、`.5`、`e2` |
| `true` / `false` / `null` | 匹配完最后一个字符 | 之后必须跟分隔符，否则整篇非法 |
| 对象 / 数组 | 读到匹配的闭合括号 | 容器完成不意味着整篇文档合法 |
| 对象键 | 读到键字符串的闭合引号 | 键名此时已完全确定 |

已完成叶值（`ValueComplete`）的顺序在任意分块方式下一致。

## 6. 事件契约

- `ObjectBegin` / `ArrayBegin`：容器开始，路径为该容器自身的路径。
- `ObjectEnd` / `ArrayEnd`：容器结束，路径同上。
- `KeyComplete`：键名已完整读出（转义与 UTF-8 已解码），路径为该键对应**值**的路径。
- `StringDelta`：字符串值的增量文本，可能被后续输入延长。
  **同一字符串的所有 `StringDelta` 合并后，恰好等于该字符串的完整文本。**
- `ValueComplete`：叶值完成，携带 `LeafValue`（`Null` / `Bool` / `Number` / `String`）。

事件数组**不要求逐项相同**（增量可以合并成不同数量的事件）；要求的是标准化后等价：

> 标准化 = 合并相邻的、路径相同的 `StringDelta`（文本拼接，区间取首尾）。
> 对同一输入的任何两种分块方式，标准化后的事件序列必须逐项相等。

## 7. 结束与完整性

`finish(reason)` 的行为：

- `EndOfStream`：补齐可终结的 token（例如末尾数字），然后检查语法栈与 UTF-8 残留。
  - 栈为空且根值已完成、其后只有空白 → `Completed(document)`。
  - 否则 → `Incomplete(pos, expected)`，`pos` 是缺失内容的位置。
- `Cancelled` / `Truncated`：**一律**返回 `Aborted(reason)`，即使此刻文本看起来恰好完整。
  取消与截断意味着模型没有说完，不能当作可交付结果。

`finish` 可能产生收尾事件（末尾数字的 `ValueComplete`），因此返回 `(收尾事件, 结果)`。

`finish` 只能在文档未结束时调用一次。重复 `finish`、`finish` 之后再 `feed` 均抛出 `AlreadyFinished`。

## 8. 错误

任何错误都使解析器进入终止状态：之后的操作抛出 `AlreadyFinished`，不尝试"恢复"。

| 错误 | 触发条件 |
|---|---|
| `InvalidSyntax` | 当前上下文不允许该字节 |
| `InvalidUtf8` | 非法首字节 / 续字节、过度长编码、代理项码位、超出 U+10FFFF、结束于未收齐的序列 |
| `InvalidEscape` | 未知转义序列，或字符串内出现未转义控制字符 |
| `InvalidNumber` | 数字词法非法（如 `01`、`1.`、`1e`、`-` 后接分隔符） |
| `InvalidUnicodeEscape` | `\u` 后不是 4 位十六进制；孤立代理项；低位代理不在 U+DC00..U+DFFF |
| `DuplicateKey` | 同一对象内重复键（V1 严格拒绝） |
| `TrailingContent` | 根值之后出现非空白内容 |
| `LimitExceeded` | 触发深度 / 单 token 字节 / 节点数 / 总输入限制 |
| `AlreadyFinished` | 调用顺序错误 |
| `InvalidLimits` | 限制参数非正数 |

## 9. 与 RFC 8259 的严格化差别

| 主题 | RFC 8259 | MoonStream |
|---|---|---|
| 重复键 | 未定义行为 | 拒绝（`DuplicateKey`） |
| 孤立代理项 | 允许出现在转义中 | 拒绝 |
| UTF-8 | 要求合法 | 额外拒绝过度长编码与超范围码点 |
| 尾随内容 | 完整文档不含 | 出现即 `TrailingContent` |
| BOM | 允许实现忽略 | **拒绝**：文档必须以值或空白开始，U+FEFF 不是合法起始 |
| 数字精度 | 建议不设上限 | 保留原始词法，不静默舍入 |

## 10. 资源限制

四个上限都必须为正数，否则 `Parser::new` 抛出 `InvalidLimits`：

- `max_depth`：容器嵌套深度。
- `max_token_bytes`：单个 token（字符串、数字、字面量）的字节数，含引号。
- `max_nodes`：值的总个数（容器与叶值都计入）。
- `max_total_bytes`：本次会话收到的总字节数。

触发时抛出 `LimitExceeded(kind, pos, allowed, actual)`。对 `max_total_bytes`，`pos` 固定为第一个
不允许消费的字节偏移，`actual = allowed + 1`；同一字节序列的错误不随输入分块方式改变。
限制边界之前若已经存在语法错误，先报告更早的语法错误。

## 11. 明确不承诺的内容

- 预览节点的单调性：字符串仍在增长、数字仍可能变长。
- 已完成子树等价于整篇文档合法。
- 任意损坏 JSON 的修复；解析器不会补齐括号或引号后交付。
- 复杂度：目标扫描成本是总输入长度的线性量级，但完整树模式、重复键检查与事件消费各自有额外成本；
  反复对整个树做快照不在此列。
- 内存恒定：解析器保留收到的全部原始字节用于构造 `CompletedDocument`，内存随文档增长。
- 安全性：不防止 prompt injection、恶意工具参数或所有资源耗尽攻击。

## 12. 部分树预览（`preview` 包）

`Preview` 是事件的**只读投影**，供 UI 逐帧渲染。它把事件应用到一棵树上，并允许按路径查询状态：

| `NodeState` | 含义 |
|---|---|
| `Missing` | 该路径不存在 |
| `Pending` | 键已知、值还不可用（刚读完冒号，或数字/字面量正在扫描）。**只出现在对象成员上** |
| `Container(kind, closed)` | 对象或数组；`closed` 表示闭合括号是否已经出现 |
| `IncompleteString(text)` | 字符串值正在增长 |
| `Complete(value)` | 已完成的叶值；`LeafValue::Null` 就是 JSON null |

规则：

- `KeyComplete` 会先建立 `Pending` 节点，因此"键已知但值还没来"与"路径不存在"可区分。
- `StringDelta` 追加到 `IncompleteString`；字符串闭合后由 `ValueComplete` 变成 `Complete`。
- 数字与字面量没有增量事件：对象成员从 `Pending` 直接跳到 `Complete`；**数组元素没有
  `KeyComplete`，因此它在值完成之前是 `Missing`**（不是 `Pending`）。
- 空预览的根路径也是 `Missing`；`node_count()` 为 0 时 `lookup(根路径)` 不会返回容器。
- `ObjectEnd` / `ArrayEnd` 只把对应容器标记为 `closed`，不改变其子节点。
- 事件顺序错误或结构冲突（例如把字符串增量送到容器路径）抛出 `PreviewError`。
- `Preview` **没有**把部分树转换成 `CompletedDocument` 的构造器；预览永远不等于可交付结果。
- 调用方用 `node_count()` 观察保留量、用 `clear()` 丢弃整棵树、用 `children(path)` 枚举容器的
  直接子节点（UI 渲染"键名还不知道"的对象时需要它）。

## 13. 多调用会话（`session` 包）

一次响应里可以有多个 tool call，它们的参数片段还会交错到达。

- 调用键是 `CallKey { response, choice, index }` 复合键。只用 `index` 不够：不同 choice 可以各有
  index 0，不同响应也会重号。
- 每个键对应且只对应一个 `Parser` 实例，因此两条流在结构上不可能被拼成同一个对象。
- 必须先 `open(key, id, name)` 才能 `feed` / `finish`；否则抛 `UnknownCall`
  （对应"没有起始上下文"的适配错误）。
- 重复 `open` 同一键是幂等的，但 id 或函数名与已有值不一致时抛 `CallIdConflict` /
  `CallNameConflict`。
- 单个调用的解析错误被包装成 `ParseFailed(key, error)`；该调用进入 `Failed` 状态并从
  `open_calls()` 移除，原始错误可由 `failure(key)` 查询；其它调用不受影响，可继续解析。
- `finish(key, reason)` 只结束该调用。取消或截断某个调用不影响其它调用。
- `open_calls()` 按注册顺序仅返回仍可继续输入的调用；`is_open` / `is_failed` / `is_finished` /
  `failure` / `offset` / `call_id` / `call_name` 用于观察状态。

适配层（`adapter` 包与 `adapters/*` 模块）把 SDK 事件翻译成上述操作，并用
`AdapterOutcome::{Ignored, Updates}` 报告结果。每个 `CallUpdate` 都携带 `CallKey`、该调用的事件和
可选结束结果，因此一个 SDK chunk 同时更新多个调用时不会丢失路由信息。适配层必须等待 SDK 的
真实终止原因；内容块结束不能代替响应正常结束。

批量收尾失败在对应更新的 `failure` 字段中报告，`result=None`；其它调用继续收尾。
调用方必须处理 failure 和 apply 的 SessionError 异常通道。没有 failure 且没有 result 才是普通增量。
