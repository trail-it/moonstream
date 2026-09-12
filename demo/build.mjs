// 构建演示用的 wasm-gc 产物，并把它复制到 www/ 供页面直接加载。
//
// 用法：node demo/build.mjs
//
// 只调用 moon，不联网。

import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");

console.log("moon build --target wasm-gc --release");
const build = spawnSync(
  process.platform === "win32" ? "moon.exe" : "moon",
  ["build", "--target", "wasm-gc", "--release"],
  { cwd: repo, stdio: "inherit" },
);
if (build.status !== 0) {
  process.exit(build.status ?? 1);
}

/** 在 _build 里找最近生成的演示 wasm。 */
function findWasm() {
  const root = join(repo, "_build", "wasm-gc");
  const found = [];
  const walk = (dir) => {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir)) {
      const path = join(dir, entry);
      if (statSync(path).isDirectory()) {
        walk(path);
      } else if (entry === "wasm.wasm") {
        found.push(path);
      }
    }
  };
  walk(root);
  if (found.length === 0) {
    throw new Error("构建产物里找不到 wasm.wasm");
  }
  found.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  return found[0];
}

const source = findWasm();
const target = join(here, "www", "moonstream_demo.wasm");
copyFileSync(source, target);
console.log(`已复制 ${source}\n     → ${target}`);
console.log("\n本地预览：在仓库根目录运行任一静态服务器，例如");
console.log("  npx --yes serve .            # 然后打开 http://localhost:3000/demo/www/");
