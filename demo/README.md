# MoonStream 离线演示（wasm-gc）

同一段 LLM tool-call 参数流，按固定字节大小分块喂入：

- **左侧**是「等整段 JSON 再解析」的应用此刻能看到的东西；
- **右侧**是 MoonStream 的部分树预览与结构事件；
- 可以调分块大小、单步、自动播放，也可以模拟截断，看到「预览保留但不可交付」。

**解析、状态判断、以及页面显示的每个字段都由 MoonBit（wasm-gc）计算**，JavaScript 只做 DOM 绘制。
产物是一个**零导入**的 wasm-gc 模块：不需要任何 JS 运行时胶水，浏览器直接实例化即可。

## 目录

| 文件 | 作用 |
|---|---|
| `wasm/demo.mbt` | 演示逻辑：分块喂入、投影预览、把状态渲染成 JSON |
| `www/host.js` | 加载 wasm、把 UTF-16 码元序列拼回字符串（浏览器与 Node 共用） |
| `www/ui.js` | 把状态画成界面 |
| `www/index.html` | 页面 |
| `check.mjs` | Node 端到端冒烟测试：加载真实 wasm 跑完整流程 |
| `build.mjs` | 构建并把 wasm 复制到 `www/` |

## 跑起来

```bash
node demo/build.mjs                 # moon build --target wasm-gc --release + 复制产物
npx --yes serve .                   # 或任意静态服务器
# 打开 http://localhost:3000/demo/www/
```

必须用 HTTP 打开：`file://` 下浏览器不允许 `fetch` 本地 wasm。

## 端到端检查

```bash
node demo/check.mjs
```

它会加载真正的 wasm-gc 产物，验证：逐块推进到 `complete`、预览等于原始文本、
事件日志里出现字段完成、逐字节分块得到同一结果、截断后状态不可交付但预览保留、
非法分块大小回退。浏览器与 Node 走的是同一份 `host.js`，所以这条检查覆盖的就是页面里的路径。

## 导出接口

| 导出 | 作用 |
|---|---|
| `moonstream_demo_reset()` | 重新开始 |
| `moonstream_demo_set_chunk_size(n)` | 设置分块大小（1..64，非法值回退到 8） |
| `moonstream_demo_step()` | 推进一块；返回事件数，`-1` 为错误 |
| `moonstream_demo_truncate()` | 用截断原因结束 |
| `moonstream_demo_render_len()` / `moonstream_demo_render_char(i)` | 逐字符读取当前状态 JSON |
