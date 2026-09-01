type t

val create : prior_high:float -> alpha_grid:float array -> t

val from_order_counts :
  prior_high:float ->
  alpha_grid:float array ->
  buys:int ->
  sells:int ->
  t

val update : t -> Domain.side -> t
val posterior_high : t -> float
val mean_alpha : t -> float
val total_mass : t -> float
val quote : Domain.market -> t -> Domain.quote
