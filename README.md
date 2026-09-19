# MoonStream

> 为 MoonBit 生态提供 **LLM 流式结构化输出的字段级增量解析与完整性契约**。

模型逐块吐出的 tool-call 参数是「永远还没写完的 JSON」。MoonStream 消费已经提取出来的参数片段字节，
跨片段保存语法状态，交付**结构事件**、**已完成叶值**、**部分树预览**和**完整性判断**——不负责连接模型，
也不假装预览就是最终结果。

状态：**参赛主包 `trail-it/moonstream` 0.1.1 已发布到 Mooncakes**；源码位于
[GitHub](https://github.com/trail-it/moonstream)。仓库中的三个 SDK 适配模块属于可选集成示例，
不作为独立参赛项目申报。

## 仓库结构

验收结果见 [2026-09-12 本地验收报告](core/docs/acceptance-2026-09-12.md)，
参赛摘要见 [SUBMISSION.md](SUBMISSION.md)，代码与依赖来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。

本仓库是一个 MoonBit workspace（`moon.work`）：

| 目录 | 内容 | 在项目中的角色 |
|---|---|---|
| [`core/`](core/) | 增量解析、事件、预览投影、多调用路由 | 参赛主包 `trail-it/moonstream` |
| [`adapters/llm_mb/`](adapters/llm_mb/) | 适配 `marianoguerra/llm@0.1.1`（llm-mb） | 可选集成示例 |
| [`adapters/mizchi_llm/`](adapters/mizchi_llm/) | 适配 `mizchi/llm@0.3.1` | 可选集成示例 |
| [`adapters/moonllm/`](adapters/moonllm/) | 适配 `DC-Z-lab/moonllm@0.1.0` | 可选集成示例 |
| [`examples/consumer/`](examples/consumer/) | 最小消费者示例 | 可运行示例 |
| [`demo/`](demo/) | 浏览器 wasm-gc 离线演示 | 展示应用 |
| [`scripts/`](scripts/) | 干净环境复现脚本 | 发布验证 |

**主库不依赖任何 LLM SDK**：每个适配层是独立模块，各自承担自己那一个 SDK 的依赖图，
因此只解析 JSON 的消费者不会被连带拉入 `async` / `mio` / 压缩库。

## 快速开始

```bash
# 在仓库根目录运行本地消费者示例
moon run --target native examples/consumer
# 在你的项目中安装：moon add trail-it/moonstream
```

```mbt
let parser = Parser::new()
let first = parser.feed(b"{\"city\":\"上")   // ObjectBegin, KeyComplete, StringDelta
let second = parser.feed(b"海\",\"count\":12}")
let (tail_events, result) = parser.finish()
match result {
  FinishResult::Completed(doc) => use(doc.to_string())
  // finish 已终止当前解析器；如需继续接收，保留原片段并创建新解析器重放。
  FinishResult::Incomplete(pos~, expected~) => report_incomplete(pos, expected)
  FinishResult::Aborted(reason~) => discard(reason)
}
```

接入真实 SDK（以 `mizchi/llm` 为例）：

```mbt
let adapter = @mizchi_llm_adapter.MizchiLlmAdapter::new(response_id="resp-1")
for event in stream_events {
  match adapter.apply(event) {
    @adapter.AdapterOutcome::Ignored => ()
    @adapter.AdapterOutcome::Updates(updates~) =>
      for update in updates {
        render(update.key, update.events)
        match update.failure {
          Some(error) => report_error(update.key, error)
          None => ()
        }
        match update.result {
          Some(result) => deliver(update.key, result)
          None => ()
        }
      }
  }
}
```

## 能力一览

- **字段级增量**：键名与已闭合叶值在流未结束时以事件交付；`{"count":1` 不会被当成数字 `1`。
- **完整性契约**：只有 `finish(EndOfStream)` 返回的 `CompletedDocument` 代表整篇文档合法。
- **分块无关**：同一输入的任何切分方式得到同一文档与标准化事件序列。
- **部分树预览**：`Preview` 把事件投影成树，区分「路径不存在 / 值还不可用 / 字符串未完成 / 已完成 / JSON null」。
- **多调用路由**：`Session` 用 `(response, choice, index)` 复合键分流，交错到达的多个 tool call 不会互相污染。
- **严格策略**：重复键、孤立代理项、非法 UTF-8、尾随内容一律拒绝；数字保留原始词法。

## 离线演示

```bash
node demo/build.mjs        # moon build --target wasm-gc --release + 复制产物
npx --yes serve .          # 打开 http://localhost:3000/demo/www/
node demo/check.mjs        # 端到端检查：用真实 wasm 产物跑完整流程
```

产物是**零导入**的 wasm-gc 模块：解析、状态判断与页面显示的每个字段都由 MoonBit 计算，
JavaScript 只负责绘制。浏览器与 Node 共用同一份 `demo/www/host.js`，所以 `check.mjs`
验证 wasm 与宿主层；页面按钮和布局需要另做浏览器验收。

## 开发

```bash
moon check --deny-warn --target all     # 工作区根目录
moon test --target native               # 131 个测试（含 native-only 的 moonllm 适配）
moon test --target js                   # 124 个测试
moon test --target wasm-gc              # 124 个测试
moon -C core package                    # 主库发布包（不含适配层）
moon bench --target native --release core/perf   # 复杂度基线
node scripts/verify-clean.mjs           # 干净环境复现（临时目录，无构建缓存）
```

## 文档

- [core/README.md](core/README.md) —— 主库使用说明
- [core/docs/semantics.md](core/docs/semantics.md) —— 语义规范（规范性文本）
- [core/docs/performance.md](core/docs/performance.md) —— 复杂度与性能基线（实测）
- [core/docs/adapters.md](core/docs/adapters.md) —— 写第三方 SDK 适配层
- [core/docs/demo-script.md](core/docs/demo-script.md) —— 三分钟演示脚本
- [core/docs/design-decisions.md](core/docs/design-decisions.md) —— 设计决策与偏差记录
- [core/docs/review-2026-09.md](core/docs/review-2026-09.md) —— 独立审查记录与缺陷修复
- [ACCEPTANCE.md](ACCEPTANCE.md) —— 验收指南（怎么用、怎么验、哪些还没做到）
- [MAINTAINING.md](MAINTAINING.md) —— 维护与发布说明
- [core/CHANGELOG.md](core/CHANGELOG.md) —— 变更日志

> [core/docs/outreach.md](core/docs/outreach.md) 里的接触草稿**一份都没发出**：
> 按项目约定，未经作者授权不主动联系维护者，也**没有**任何"已被采用/获官方推荐"的说法。

## 许可证

Apache-2.0，见 [core/LICENSE](core/LICENSE)。
