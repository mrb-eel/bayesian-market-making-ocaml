val buy_chance : alpha:float -> Domain.fundamental -> float

val side_likelihood :
  alpha:float -> fundamental:Domain.fundamental -> Domain.side -> float

val posterior_high : prior_high:float -> alpha:float -> Domain.side -> float
val fair_value : Domain.market -> float -> float

val conditional_value :
  Domain.market -> prior_high:float -> alpha:float -> Domain.side -> float

val competitive_quote :
  Domain.market -> prior_high:float -> alpha:float -> Domain.quote

val log_odds : float -> float
val probability_from_log_odds : float -> float

val posterior_from_order_counts :
  prior_high:float -> alpha:float -> buys:int -> sells:int -> float
