type t

val create : prior_high:float -> alpha_grid:float array -> window:int -> t
val update : t -> Domain.side -> t
val posterior_high : t -> float
val mean_alpha : t -> float
val quote : Domain.market -> t -> Domain.quote
val observation_count : t -> int
