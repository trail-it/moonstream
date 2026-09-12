# 维护与发布说明

面向接手这个仓库的人（包括未来的自己）。本文说明项目边界、兼容性承诺、发布流程与依赖策略。

## 1. 项目边界

MoonStream 只做一件事：**消费 LLM 流式结构化输出的参数片段字节，给出结构事件、部分树预览与完整性判断**。

长期不做的事（收到请求也要先讨论是否越界）：

- 通用 Agent 框架、模型 HTTP SDK、SSE 分帧重写、RAG、工具执行。
- JSON Schema 引擎（解析完成后接入 `moon_zod` / `moonschema` 这类现有校验器）。
- 任意损坏 JSON 的修复。V1 明确不做；若将来提供修复建议，必须返回**单独的候选数据与修改记录**，
  不能冒充原始合法结果。
- 通用 JSON 包装/查询（那是 `jsonx`、`jsonl`、`jqx` 的领域）。

## 2. 兼容性基线

**规范性文本**：[core/docs/semantics.md](core/docs/semantics.md)。它是兼容性判断的依据：
实现与它冲突就是 bug，无论测试怎么写。

**接口基线**：每个包的 `pkg.generated.mbti` 提交进版本控制。`moon info` 之后 `git diff` 为空
说明公开接口没变。私有实现类型（`ParserState`、`Node`、`CallEntry` …）不出现在 `.mbti` 里，
因此内部重构不会造成接口 diff。

**行为基线**：`core/*_test.mbt` 中的 fixture 与不变量。重点保住这几条：

1. 任意分块方式得到同一最终文档、同一错误位置、标准化后等价的事件序列。
2. 字符串增量合并后恰好覆盖该字符串的完整文本。
3. 只有 `EndOfStream` 能产生 `CompletedDocument`。
4. 重复键、孤立代理项、非法 UTF-8、尾随内容一律拒绝。

### 什么算破坏性变更

- 公开类型、函数、构造器、错误分支的增删改（`.mbti` 出现 diff）。
- 事件的语义变化：例如某个输入从"不产生事件"变成"产生事件"。
- 严格策略的**放松**（例如开始接受重复键）：这是行为变化，即使接口没动。
- 严格策略的**收紧**也可能破坏使用方：例如原本能通过的数字现在被拒绝。

破坏性变更必须：升 minor（0.x 期间为 minor）、在 `CHANGELOG.md` 写明迁移方式、
在 PR 描述里贴出 `.mbti` diff。

## 3. 发布流程

```bash
# 1. 全绿
moon check --deny-warn --target all
moon test --target wasm-gc && moon test --target js && moon test --target native
node demo/build.mjs && node demo/check.mjs
node scripts/verify-clean.mjs

# 2. 接口与格式无意外变化
moon fmt && moon info && git diff --exit-code

# 3. 发布包只含主库
moon -C core package --list      # 不应出现 adapters/

# 4. 版本与变更日志
#    更新 core/moon.mod 的 version，更新 CHANGELOG.md

# 5. 发布（逐个模块，模块命令要在模块目录里跑）
moon -C core publish
moon -C adapters/llm_mb publish
moon -C adapters/mizchi_llm publish
moon -C adapters/moonllm publish

# 6. 在干净消费者项目里真实安装，跑一次示例
mkdir /tmp/consumer && cd /tmp/consumer && moon new --user <you> consumer
moon add trail-it/moonstream
# 写一个最小示例并 moon run
```

**只有第 6 步成功，才可以把"已发布可用"写进 README。** 注册表上的 build success 不能替代
真实安装。

## 4. 工具链升级

每次升级 `moon` / `moonc` 之后：

1. 跑 `node scripts/verify-clean.mjs`。
2. 跑 `moon bench --target native --release core/perf`，与
   [core/docs/performance.md](core/docs/performance.md) 的基线对比；数量级变化要在该文档里记录。
3. 检查适配层的 SDK 是否有了"能在新工具链上编译的最新版"：本仓库把
   `marianoguerra/llm` 固定在 0.1.1、`mizchi/llm` 固定在 0.3.1，原因是这两个版本的传递依赖
   （`moonbitlang/async`）与当时的工具链兼容（见 `core/docs/design-decisions.md` D9）。
   升级后应当尝试改回最新版，并用适配层测试验证 `StreamEvent` 接口未变。
4. `moon fmt && moon info && git diff` 必须只有预期变化。

## 5. 依赖策略

| 位置 | 策略 |
|---|---|
| `core/`（主库） | **零第三方依赖**，只用 `moonbitlang/core`。新增任何依赖都需要先证明无法用标准库完成 |
| `adapters/*` | 每个适配层单独一个模块，只依赖它适配的那一个 SDK；固定精确版本 |
| `demo/` | 只依赖主库；wasm-gc only |
| `scripts/` | 只用 Node 标准库，不引入 npm 依赖 |

许可证：本项目 Apache-2.0。引入第三方代码或 fixture 前必须确认其许可证允许再分发，
并在 `CHANGELOG.md` 或相关文档里记录来源与许可证。**不复制**参考实现的代码，
参考实现只作为测试 oracle。

## 6. 缺陷处理

- 收到报告后先写一个**能复现的最小输入**（字节序列 + 分块方式），加进 `*_test.mbt` 让它失败，
  再修。修完保留该测试。
- 解析错误优先给**位置**：`ParseError` 的 `pos` 必须是绝对字节偏移，且与分块方式无关。
- 语义争议以 `semantics.md` 为准；要改语义就先改那份文档，再改实现和测试。

## 7. 加一个新的适配层

见 [core/docs/adapters.md](core/docs/adapters.md)。要点：单独建模块、固定 SDK 版本、
用 SDK 真实类型写测试、不要改变主库语义。

## 8. 安全与限制

- 解析器只保证**语法**正确性，不保证模型意图、不防止 prompt injection、不防止所有资源耗尽。
- 资源限制（深度/token/节点/总字节）必须保持可配置且有默认值；不要为了"更好用"而放宽默认值。
- `CompletedDocument` 不代表获得执行授权。调用方在产生副作用前仍要自己做业务校验。

## 9. 当前维护者

单人维护（Mooncakes 命名空间 `Magic486`）。尚未建立外部贡献者流程；收到第一个外部 PR 时
再补 `CONTRIBUTING.md`。
