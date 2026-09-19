# 验收指南

2026-09-12 实际检查及修复结果见 [本地验收报告](core/docs/acceptance-2026-09-12.md)。
本指南为复现步骤；未运行的项目不应按预期列当作通过证据。

面向验收人：**怎么用**、**怎么验**、**哪些还没做到**。所有命令都在 Windows PowerShell 下实测过；
其它平台把 `moon.exe` 换成 `moon` 即可。

## 0. 环境

| 项 | 要求 | 本机实测 |
|---|---|---|
| MoonBit | 能编译 `.mbt` 的工具链 | `moon 0.1.20260713 (75c7e1f)`、`moonc v0.10.4+2cc641edf` |
| Node.js | 24.x（本地验证版本；演示需要 wasm-gc 支持） | v24.19.0 |
| 静态服务器 | 可选，浏览器演示用 | `npx --yes serve .` |

```powershell
moon version --all        # 确认工具链可用
node --version            # 确认 Node 可用
```

---

## 1. 怎么用

### A. 最小消费者示例（最快，30 秒，不需要浏览器）

```powershell
cd moonstream
moon run --target native examples/consumer
```

预期输出：

```text
  当前预览: {"city":…,…}
  当前预览: {"city":…,…}
完成字段 $.city = 上海
完成字段 $.count = 12
  当前预览: {"city":"上海","count":12}
可交付: {"city":"上海","count":12}（28 字节）
```

看点在第二行：第 2 个分块只有一个汉字的前半个字节（UTF-8 被切开），预览仍显示 Pending，
收齐后才变成完整值。**前两行没有"完成字段"，因为字符串还没闭合——这就是"不猜测"。**

### B. 离线回放工具（看分块过程与错误定位）

```powershell
moon -C core run --target native cmd/replay                     # 内置样本，逐块打印事件
moon -C core run --target native cmd/replay -- '[1,2' 2         # 截断：预览保留但不可交付
moon -C core run --target native cmd/replay -- '01' 1           # 前导零：报 InvalidNumber(pos=1)
```

第三条预期结尾：`解析错误: InvalidNumber(pos=1, lexeme="01")`——错误带**绝对字节位置**。

### C. 浏览器 wasm-gc 演示（两栏对照）

```powershell
node demo/build.mjs        # 构建 wasm-gc 产物并复制到 demo/www/
npx --yes serve .          # 或任意静态服务器
# 浏览器打开 http://localhost:3000/demo/www/
```

页面左侧是「等整段 JSON」的应用能看到的东西，右侧是 MoonStream 的逐字段预览。
可以调分块大小（1 字节起）、单步、自动播放、模拟截断。

**必须用 HTTP 打开**：`file://` 下浏览器不允许 `fetch` 本地 wasm。

产物是**零导入**的 wasm-gc 模块，浏览器直接实例化；解析、状态判断与页面显示的每个字段
都由 MoonBit 计算。不联网、不调用模型。

### D. 在你自己的项目里用

`trail-it/moonstream` 已发布到 Mooncakes，可直接加入现有 MoonBit 项目：

```bash
moon add trail-it/moonstream@0.1.1
```

1. 在仓库里新建一个模块目录，例如 `myapp/`：

   `myapp/moon.mod`
   ```text
   name = "you/myapp"
   version = "0.1.0"
   import {
     "trail-it/moonstream@0.1.1",
   }
   ```

   `myapp/moon.pkg`
   ```text
   import {
     "trail-it/moonstream" @moonstream,
     "trail-it/moonstream/preview" @preview,
     "moonbitlang/core/encoding/utf8" @utf8,
   }
   options(
     "is-main": true,
   )
   ```

2. 把 `"./myapp"` 加进仓库根的 `moon.work` 的 `members` 列表。

3. 写代码（可照抄 `examples/consumer/main.mbt`），然后：

   ```powershell
   moon run --target native myapp
   ```

要点：`moon.mod` 只写**模块级**依赖（带版本号），包级 `import` 写在 `moon.pkg` 里。

---

## 2. 验收清单

| # | 验收项 | 命令 | 预期 / 判定 |
|---|---|---|---|
| 1 | 主语言是 MoonBit | `moon version --all` | 工具链可用；代码为 `.mbt` |
| 2 | 源码结构清晰、能完成声明的功能 | 见第 1 节 A/B/C | 三种用法都能跑出预期输出 |
| 3 | README 说明目标、安装、用法、示例 | 读 `README.md`、`core/README.md` | 含快速开始与可复现示例 |
| 4 | 至少一个可运行示例 | `moon run --target native examples/consumer` | 输出与本文一致 |
| 5 | 完整测试覆盖核心路径 | `moon test --target native` | **131 passed, 0 failed** |
| 6 | 三后端一致 | `moon test --target wasm-gc` / `--target js` | 各 **124 passed, 0 failed** |
| 7 | CI 覆盖检查/构建/测试 | 读 `.github/workflows/ci.yml` | 含 `check --target all`、三后端测试、演示检查、打包边界断言 |
| 8 | 工程质量（零告警） | `moon check --deny-warn --target all` | 无输出（0 error 0 warning） |
| 9 | 干净环境可复现 | `node scripts/verify-clean.mjs` | 结尾 `干净环境复现：全部通过` |
| 10 | 示例端到端（真实 wasm 产物） | `node demo/check.mjs` | `全部通过`（17 项） |
| 11 | 复杂度可复现 | `moon bench --target native --release core/perf` | 打印各规模耗时；解读见 `core/docs/performance.md` |
| 12 | 语义有规范、非口头承诺 | 读 `core/docs/semantics.md` | 含承诺与**不承诺**清单 |
| 13 | 许可证 | 根目录 `LICENSE` 及各发布模块的 `LICENSE` | Apache-2.0（OSI 认可） |
| 14 | 发布到 mooncakes.io | `moon add trail-it/moonstream@0.1.1` | 主包可从注册表安装 |
| 15 | 仓库公开可访问 | [GitHub](https://github.com/trail-it/moonstream) | `main` 分支公开，提交历史与 CI 可审查 |

以下命令检查功能、演示与干净副本；性能基准另见第 11 项：

```powershell
moon check --deny-warn --target all
moon test --target wasm-gc; moon test --target js; moon test --target native
node demo/build.mjs; node demo/check.mjs
node scripts/verify-clean.mjs
```

---

## 3. 怎么确认测试不是摆设

全绿本身不能证明校验有效。做一次**变异测试**：故意改坏一处，看对应测试是否变红。

```powershell
cd moonstream
Copy-Item core\scanner.mbt core\scanner.mbt.bak

# 故意放行重复键（把 raise ParseError::DuplicateKey(...) 换成 ()）
# 用编辑器把 core\scanner.mbt 里 close_string 中的 DuplicateKey 那行改成：
#     () // 故意改坏

moon test core --target native -f "*重复键*"
# 预期：1 failed —— "重复键必须失败"

Move-Item core\scanner.mbt.bak core\scanner.mbt -Force   # 还原
moon test core --target native -f "*重复键*"             # 预期：1 passed
```

其它可用的"改坏点"与对应会变红的测试：

| 改坏什么 | 应失败的测试 |
|---|---|
| 放行重复键 | `negative_test.mbt` "重复键必须失败" |
| 数字提前完成（去掉分隔符确认） | `number_test.mbt` "数字只有在被分隔符确认后才完成" |
| `finish` 不检查语法栈 | `prefix_test.mbt` "每个字节前缀的 finish 结果与独立 oracle 一致" |
| 字符串增量不合并成完整文本 | `chunk_test.mbt` "穷举所有单切点二分" |
| 根节点不再区分空预览 | `preview_test.mbt` "节点数与清空" |

看测试清单（证明覆盖面，而不是只看数字）：

```powershell
moon test core --target native --outline      # 列出每个测试的名字与文件
moon test core --target native -f "*分块*" -v # 只跑名字含"分块"的
moon test core\api_test.mbt --target native   # 只跑一个文件
```

---

## 4. 发布状态与后续事项

| 项 | 现状 | 影响 |
|---|---|---|
| 发布到 mooncakes.io | `trail-it/moonstream` 0.1.1 已发布；三个适配模块仅作为仓库内集成示例 | 消费者可直接 `moon add` 主包 |
| GitHub / Gitlink 仓库 | GitHub 仓库、提交历史和 CI 已公开；Gitlink 同步待完成 | GitHub 已满足源码审查，后续补充国产托管镜像 |
| 外部采用 / 官方推荐 | **没有任何外部反馈或采用记录** | `core/docs/outreach.md` 里只有草稿，一份都没发出 |

其余（代码、测试、CI、文档、示例、许可证、演示）都已就绪并可按本文复现。

---

## 5. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `moon add trail-it/moonstream` 失败 | 先运行 `moon update`，再指定 `@0.1.1`；仍失败时检查网络和 Mooncakes 登录状态 |
| 浏览器页面空白、控制台报 fetch 失败 | 用了 `file://` 打开；改用 HTTP 服务器 |
| `node demo/check.mjs` 报找不到 wasm | 先跑 `node demo/build.mjs`（它会复制页面实际加载的 wasm 文件） |
| 适配层 `moonllm` 在 js / wasm-gc 下"消失" | 该 SDK 只支持 native，适配模块声明了 `supported_targets = "native"`，其它后端自动跳过 |
| 想改回更新的 SDK 版本 | 见 `core/docs/design-decisions.md` D9：本机工具链编译不了更新的 `moonbitlang/async`；升级工具链后需重新验证 SDK 兼容性 |
| 数字精度 | 事件流里的 `NumberLiteral` 保留原始词法；`CompletedDocument::to_json` 用核心 `Json`（最短往返表示），详见 `core/docs/semantics.md` §9 |
