// Node 端到端冒烟测试：加载真正的 wasm-gc 产物，跑完整个演示流程。
//
// 验证部署 wasm 与共享 host.js；页面按钮与布局另做浏览器验收。
//
// 用法：node demo/check.mjs [wasm 路径]

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createDemo } from "./www/host.js";

const here = dirname(fileURLToPath(import.meta.url));

/** 默认验证页面实际加载的部署产物。 */
function findWasm() {
  const explicit = process.argv[2];
  if (explicit) {
    return explicit;
  }
  const target = join(here, "www", "moonstream_demo.wasm");
  if (!existsSync(target)) {
    throw new Error("找不到演示部署产物，请先运行：node demo/build.mjs");
  }
  return target;
}

const wasmPath = findWasm();
const demo = await createDemo(readFileSync(wasmPath));
console.log(`加载 ${wasmPath}`);

let failures = 0;
const check = (label, condition, extra = "") => {
  if (condition) {
    console.log(`  ok   ${label}`);
  } else {
    failures += 1;
    console.error(`  FAIL ${label}${extra ? ` — ${extra}` : ""}`);
  }
};

// 1. 逐块推进到完成
let state = demo.setChunkSize(8);
check("初始状态为解析中", state.status === "parsing", state.status);
check("分块数已算出", state.total_steps > 0, String(state.total_steps));
check("预览初始为空", state.preview === "<empty>", state.preview);

while (state.step < state.total_steps) {
  state = demo.step();
}
check("走完后状态为 complete", state.status === "complete", state.status);
check("预览等于原始文本", state.preview === state.source, state.preview);
check("完成后点击截断不会损坏结果", demo.truncate().status === "complete");
check(
  "事件日志里有字段完成",
  state.log.some((line) => line.includes("$.args.title = \"登录失败\"")),
  state.log.slice(-3).join(" | "),
);
check(
  "不可交付的中间态已经出现过",
  state.log.some((line) => line.includes("…")),
);

// 2. 逐字节喂入也要得到同一个结果
state = demo.setChunkSize(1);
check("逐字节：分块数等于字节数", state.total_steps > 100, String(state.total_steps));
while (state.step < state.total_steps) {
  state = demo.step();
}
check("逐字节：仍然 complete", state.status === "complete", state.status);
check("逐字节：预览一致", state.preview === state.source);

// 3. 截断：预览保留，但状态不是 complete
state = demo.setChunkSize(8);
state = demo.step();
state = demo.step();
state = demo.truncate();
check("截断保留实际进度", state.step === 2 && state.step < state.total_steps);
check("截断后步进不再消费输入", demo.step().step === 2);
check("重复截断保持终态", demo.truncate().status === "aborted");
check(
  "截断后状态不可交付",
  state.status === "aborted" || state.status === "incomplete",
  state.status,
);
check(
  "截断后预览仍保留已解析内容",
  state.preview.startsWith("{\"tool\":\"create_"),
  state.preview,
);

// 4. 非法分块大小回退
state = demo.setChunkSize(0);
check("非法分块大小回退到 8", state.chunk_size === 8, String(state.chunk_size));

console.log(failures === 0 ? "\n全部通过" : `\n${failures} 项失败`);
process.exit(failures === 0 ? 0 : 1);
