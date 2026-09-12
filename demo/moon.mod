// 离线浏览器演示模块。
//
// 它只依赖主库，把「同一段参数流在 MoonStream 下的逐字段演进」计算成一份
// JSON 状态，交给宿主页面渲染。所有解析与状态判断都在 MoonBit 里完成，
// JavaScript 只做 DOM 绘制。
name = "trail-it/moonstream_demo"

version = "0.1.0"

readme = "README.md"

repository = ""

license = "Apache-2.0"

keywords = [ "moonbit", "wasm-gc", "demo", "llm", "streaming" ]

preferred_target = "wasm-gc"

description = "Offline wasm-gc demo: incremental tool-call argument rendering."

import {
  "trail-it/moonstream@0.1.0",
}
