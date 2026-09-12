// MoonStream 演示的宿主层。
//
// 这一层只做两件事：加载 wasm-gc 模块，以及把模块导出的 UTF-16 码元序列
// 拼回字符串。所有解析、状态判断与展示数据都由 MoonBit 计算。
//
// 同一份代码在浏览器和 Node 里都能跑：传入 ArrayBuffer 即可。

/**
 * 从字节加载演示模块。
 * @param {ArrayBuffer | Uint8Array} wasmBytes
 */
export async function createDemo(wasmBytes) {
  const bytes = wasmBytes instanceof Uint8Array ? wasmBytes : new Uint8Array(wasmBytes);
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const ex = instance.exports;

  const readState = () => {
    const len = ex.moonstream_demo_render_len();
    let text = "";
    for (let i = 0; i < len; i++) {
      text += String.fromCharCode(ex.moonstream_demo_render_char(i));
    }
    return JSON.parse(text);
  };

  return {
    /** 重新开始。 */
    reset() {
      ex.moonstream_demo_reset();
      return readState();
    },
    /** 设置分块大小（字节）。 */
    setChunkSize(size) {
      ex.moonstream_demo_set_chunk_size(size);
      return readState();
    },
    /** 推进一个分块；返回最新状态。 */
    step() {
      ex.moonstream_demo_step();
      return readState();
    },
    /** 用截断原因结束。 */
    truncate() {
      ex.moonstream_demo_truncate();
      return readState();
    },
    /** 只读当前状态。 */
    state() {
      return readState();
    },
  };
}

/**
 * 在浏览器里按 URL 加载。
 * @param {string} url
 */
export async function loadDemoFromUrl(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`无法加载 ${url}: HTTP ${response.status}`);
  }
  return createDemo(await response.arrayBuffer());
}
