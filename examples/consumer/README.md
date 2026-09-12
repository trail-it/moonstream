# 最小消费者示例

像外部使用者一样，只用 MoonStream 的公开 API。

```powershell
moon run --target native examples/consumer
```

输出：

```text
  当前预览: {"city":…,…}
  当前预览: {"city":"上…,…}
完成字段 $.city = 上海
完成字段 $.count = 12
  当前预览: {"city":"上海","count":12}
可交付: {"city":"上海","count":12}（28 字节）
```

演示三件事：

1. **参数片段逐块到达时，已完成的字段立刻可用**（`ValueComplete` 事件）。
2. **半个汉字跨块也能正确拼接**：第 2 个分块只有一个 UTF-8 字符的前半个字节，
   预览先显示 `上…`，收齐后才变成完整值。
3. **只有正常结束才得到可交付结果**：中途只有预览，`finish()` 之后才有 `CompletedDocument`。

注意第 1、2 行没有"完成字段"——字符串还没闭合，库不会猜。

想在自己的模块里照抄，见 [ACCEPTANCE.md](../../ACCEPTANCE.md) 第 1 节 D。
