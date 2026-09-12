// 适配 mizchi/llm@0.3.1（生态里下载量最高的 MoonBit LLM 客户端）。
//
// 该 SDK 的流式工具调用同样以文本增量交付参数，本适配器把它的
// `StreamEvent::ToolCallDelta(input_delta)` 直接接进 MoonStream 会话。
name = "trail-it/mizchi_llm_adapter"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/trail-it/moonstream"

license = "Apache-2.0"

keywords = [ "llm", "adapter", "streaming", "tool-call" ]

preferred_target = "wasm-gc"

description = "Adapter mapping mizchi/llm streaming events onto MoonStream sessions."

import {
  "trail-it/moonstream@0.1.0",
  "mizchi/llm@0.3.1",
}
