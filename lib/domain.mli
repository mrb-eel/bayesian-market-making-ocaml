type fundamental = Low | High

type side = Buy | Sell

type trader_kind = Informed | Noise

type market = {
  low_value : float;
  high_value : float;
  prior_high : float;
}

type quote = {
  bid : float;
  ask : float;
}

val make_market : low_value:float -> high_value:float -> prior_high:float -> market
val value_of_fundamental : market -> fundamental -> float
val opposite_side : side -> side
val string_of_side : side -> string
val string_of_fundamental : fundamental -> string
val string_of_trader_kind : trader_kind -> string
