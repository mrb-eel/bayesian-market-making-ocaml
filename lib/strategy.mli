type t

val static : prior_high:float -> assumed_alpha:float -> t
val bayesian : prior_high:float -> assumed_alpha:float -> t
val joint : prior_high:float -> alpha_grid:float array -> t
val rolling_joint : prior_high:float -> alpha_grid:float array -> window:int -> t

val label : t -> string
val belief_high : t -> float
val alpha_estimate : t -> float
val quote : Domain.market -> t -> Domain.quote
val observe : t -> Domain.side -> t
