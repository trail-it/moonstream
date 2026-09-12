// 浏览器界面：只负责把 MoonBit 算出的状态画出来。
// 这里没有任何 JSON 解析逻辑——它读到的每个字段都来自 wasm 模块。

const STATUS_TEXT = {
  parsing: "解析中",
  complete: "已完成（可交付）",
  incomplete: "未完成（不可交付）",
  aborted: "已取消 / 截断（不可交付）",
  error: "解析错误",
};

/**
 * @param {ReturnType<import("./host.js").createDemo>} demo
 */
export function mount(demo) {
  const el = (id) => document.getElementById(id);
  const previewEl = el("preview");
  const logEl = el("log");
  const statusEl = el("status");
  const chunkEl = el("chunk");
  const progressEl = el("progress");
  const rawEl = el("raw");
  const resultEl = el("result");

  let state = demo.reset();
  let timer = null;

  function render(next) {
    state = next;
    previewEl.textContent = state.preview;
    statusEl.textContent = STATUS_TEXT[state.status] ?? state.status;
    statusEl.dataset.status = state.status;
    chunkEl.textContent = JSON.stringify(state.last_chunk);
    progressEl.textContent = `${state.step} / ${state.total_steps}`;
    // 左侧对照：等整段 JSON 的应用此刻能看到什么
    const delivered = state.status === "complete";
    rawEl.textContent = delivered ? state.detail : "（等待完整 JSON…）";
    resultEl.textContent = delivered
      ? state.detail
      : state.detail
        ? `不可交付：${state.detail}`
        : "";
    logEl.replaceChildren(
      ...state.log.slice(-14).map((line) => {
        const li = document.createElement("li");
        li.textContent = line;
        return li;
      }),
    );
    logEl.scrollTop = logEl.scrollHeight;
  }

  function stop() {
    if (timer !== null) {
      clearInterval(timer);
      timer = null;
      el("play").textContent = "自动播放";
    }
  }

  el("step").addEventListener("click", () => {
    stop();
    render(demo.step());
  });
  el("play").addEventListener("click", () => {
    if (timer !== null) {
      stop();
      return;
    }
    el("play").textContent = "暂停";
    timer = setInterval(() => {
      const next = demo.step();
      render(next);
      if (next.step >= next.total_steps || next.status !== "parsing") {
        stop();
      }
    }, 260);
  });
  el("reset").addEventListener("click", () => {
    stop();
    render(demo.reset());
  });
  el("truncate").addEventListener("click", () => {
    stop();
    render(demo.truncate());
  });
  el("chunk-size").addEventListener("change", (event) => {
    stop();
    render(demo.setChunkSize(Number(event.target.value)));
  });

  render(state);
}
