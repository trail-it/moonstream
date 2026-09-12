// 适配 DC-Z-lab/moonllm@0.1.0。
//
// 这个模块单独存在：moonllm 依赖 moonbitlang/async@0.20.1 与 oboard/mio，
// 且只支持 native 后端；把它与 marianoguerra/llm 放在同一个模块会导致
// async 版本冲突（见 README 的"版本与后端约束"）。
name = "trail-it/moonllm_adapter"

version = "0.1.1"

readme = "README.md"

repository = "https://github.com/trail-it/moonstream"

license = "Apache-2.0"

keywords = [ "llm", "adapter", "streaming", "tool-call" ]

preferred_target = "native"

description = "Adapter mapping DC-Z-lab/moonllm streaming chunks onto MoonStream sessions."

import {
  "trail-it/moonstream@0.1.1",
  "DC-Z-lab/moonllm@0.1.0",
}
