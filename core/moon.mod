// MoonStream 主库：核心解析、预览与多调用路由。
// 它**不依赖任何 LLM SDK**；真实 SDK 的适配在 workspace 成员 ./adapters 中。
// See https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
name = "trail-it/moonstream"

version = "0.1.1"

readme = "README.md"

repository = "https://github.com/trail-it/moonstream"

license = "Apache-2.0"

keywords = [ "llm", "json", "streaming", "parser", "incremental" ]

preferred_target = "wasm-gc"

description = "Incremental, chunk-invariant parsing of streaming JSON tool-call arguments."
