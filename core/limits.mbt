///|
/// 解析器的资源限制。
///
/// 四个上限都必须为正数；`Parser::new` 会拒绝非法组合。
/// 限制只约束解析器自身的开销，不承诺能抵御任意恶意输入。
pub(all) struct Limits {
  max_depth : Int
  max_token_bytes : Int
  max_nodes : Int
  max_total_bytes : Int
} derive(Eq, Debug, ToJson)

///|
/// 默认的严格限制：深度 128、单 token 1 MiB、节点数 1 Mi、总输入 64 MiB。
pub fn Limits::strict() -> Limits {
  {
    max_depth: 128,
    max_token_bytes: 1048576,
    max_nodes: 1048576,
    max_total_bytes: 67108864,
  }
}

///|
/// 自定义限制。任一参数非正数即抛出 `InvalidLimits`。
pub fn Limits::new(
  max_depth? : Int = 128,
  max_token_bytes? : Int = 1048576,
  max_nodes? : Int = 1048576,
  max_total_bytes? : Int = 67108864,
) -> Limits raise ParseError {
  validate_limits(max_depth~, max_token_bytes~, max_nodes~, max_total_bytes~)
  { max_depth, max_token_bytes, max_nodes, max_total_bytes }
}

///|
fn validate_limits(
  max_depth~ : Int,
  max_token_bytes~ : Int,
  max_nodes~ : Int,
  max_total_bytes~ : Int,
) -> Unit raise ParseError {
  if max_depth <= 0 {
    raise ParseError::InvalidLimits(detail="max_depth 必须为正数")
  }
  if max_token_bytes <= 0 {
    raise ParseError::InvalidLimits(detail="max_token_bytes 必须为正数")
  }
  if max_nodes <= 0 {
    raise ParseError::InvalidLimits(detail="max_nodes 必须为正数")
  }
  if max_total_bytes <= 0 {
    raise ParseError::InvalidLimits(detail="max_total_bytes 必须为正数")
  }
}
