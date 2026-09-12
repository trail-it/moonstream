# README 示例（参与编译与测试）

本文件与 [README.md](README.md) 的示例保持同步，存在的唯一目的是让 README 中的代码真正被
`moon check` / `moon test` 覆盖——README.md 本身是普通 Markdown，其中的代码块不会被工具链编译。

## 快速开始

```mbt check
///|
test {
  let parser = Parser::new()
  // 逐块喂入已经提取出来的参数片段字节
  let first = parser.feed(b"{\"city\":\"上")
  inspect(first.length(), content="3")
  let second = parser.feed(b"海\",\"count\":12}")
  inspect(second.length(), content="5")
  // 只有正常结束才可能得到可交付的文档
  let (_, result) = parser.finish()
  match result {
    FinishResult::Completed(doc) =>
      inspect(doc.to_string(), content="{\"city\":\"上海\",\"count\":12}")
    _ => fail("应当完成")
  }
}
```

## 资源限制

```mbt check
///|
test {
  let limits = Limits::new(max_depth=3)
  let parser = Parser::new(limits~)
  let failed = try {
    let _ = parser.feed(b"[[[[1]]]]")
    false
  } catch {
    ParseError::LimitExceeded(..) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(failed, content="true")
}
```

## 事件路径

```mbt check
///|
test {
  let path = Path::root().child_key("items").child_index(0).child_key("name")
  inspect(path.to_string(), content="$.items[0].name")
}
```

## 部分树预览（M2）

```mbt check
///|
test {
  let parser = Parser::new()
  let preview = @preview.Preview::new()
  for event in parser.feed(b"{\"city\":\"上") {
    preview.apply(event)
  }
  // 字符串正在增长，不是最终值
  inspect(preview.to_preview_string(), content="{\"city\":\"上…,…}")
  inspect(
    preview.lookup(Path::root().child_key("city"))
    is @preview.NodeState::IncompleteString(..),
    content="true",
  )
}
```

## 多调用路由（M2）

```mbt check
///|
test {
  let session = @session.Session::new()
  let first = @session.CallKey::new(response="resp-1", choice=0, index=0)
  let second = @session.CallKey::new(response="resp-1", choice=0, index=1)
  session.open(first, id=Some("call_a"), name=Some("create_ticket"))
  session.open(second, id=Some("call_b"), name=Some("send_mail"))
  // 片段交错到达
  let _ = session.feed(first, b"{\"title\":\"登")
  let _ = session.feed(second, b"{\"to\":\"a@b.c\"}")
  let _ = session.feed(first, b"录失败\"}")
  let (_, first_result) = session.finish(first)
  let (_, second_result) = session.finish(second)
  inspect(
    match first_result {
      FinishResult::Completed(doc) => doc.to_string()
      _ => "?"
    },
    content="{\"title\":\"登录失败\"}",
  )
  inspect(
    match second_result {
      FinishResult::Completed(doc) => doc.to_string()
      _ => "?"
    },
    content="{\"to\":\"a@b.c\"}",
  )
}
```
