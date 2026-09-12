// 适配 marianoguerra/llm（仓库 llm-mb）。
//
// 版本固定在 0.1.1：0.2.0 起该 SDK 要求 moonbitlang/async@0.21.2，而本机
// 工具链（moon 0.1.20260713 / moonc 0.10.4）无法解析 async 0.21.2 的 native
// 源码；0.1.1 的 StreamEvent 接口与 0.3.0 完全一致，只需要 async 0.20.3，
// 可与 moonllm 适配模块共存。
//
// 这个模块单独存在：每个适配层只承担自己那一个 SDK 的依赖图，
// 这样任何 SDK 的传递依赖都不会进入主库 trail-it/moonstream。
name = "trail-it/llm_mb_adapter"

version = "0.1.1"

readme = "README.md"

repository = "https://github.com/trail-it/moonstream"

license = "Apache-2.0"

keywords = [ "llm", "adapter", "streaming", "tool-call" ]

preferred_target = "wasm-gc"

description = "Adapter mapping marianoguerra/llm streaming events onto MoonStream sessions."

import {
  "trail-it/moonstream@0.1.1",
  "marianoguerra/llm@0.1.1",
}
