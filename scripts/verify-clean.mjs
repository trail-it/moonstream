// 干净环境复现脚本：把仓库复制到临时目录（不含 _build / .mooncakes / .git），
// 在没有任何本地构建状态的副本里跑完整的检查、测试与演示。
//
// 用法：node scripts/verify-clean.mjs
//
// 目的：证明结果不依赖开发机上的构建缓存或本地路径。依赖仍从 mooncakes 注册表解析，
// 所以第一次运行需要网络。

import { cpSync, mkdtempSync, existsSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname, basename } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const target = mkdtempSync(join(tmpdir(), "moonstream-clean-"));
const moon = process.platform === "win32" ? "moon.exe" : "moon";
const node = process.execPath;

console.log(`复制 ${repo}\n  → ${target}`);
cpSync(repo, target, {
  recursive: true,
  filter: (src) => {
    const name = basename(src);
    return name !== "_build" && name !== ".mooncakes" && name !== ".git";
  },
});

const steps = [
  ["检查（全部后端，警告即错误）", moon, ["check", "--deny-warn", "--target", "all"]],
  ["测试 wasm-gc", moon, ["test", "--target", "wasm-gc"]],
  ["测试 js", moon, ["test", "--target", "js"]],
  ["测试 native", moon, ["test", "--target", "native"]],
  ["构建 wasm-gc 演示", node, ["demo/build.mjs"]],
  ["演示端到端检查", node, ["demo/check.mjs"]],
  ["主库打包", moon, ["-C", "core", "package"]],
];

let failed = null;
for (const [label, command, args] of steps) {
  console.log(`\n=== ${label} ===`);
  const result = spawnSync(command, args, { cwd: target, stdio: "inherit" });
  if (result.status !== 0) {
    failed = label;
    break;
  }
}

if (failed === null) {
  rmSync(target, { recursive: true, force: true });
  console.log("\n干净环境复现：全部通过");
} else {
  console.error(`\n干净环境复现失败于：${failed}`);
  console.error(`副本保留在 ${target} 以便排查`);
  process.exit(1);
}
