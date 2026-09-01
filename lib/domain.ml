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

let make_market ~low_value ~high_value ~prior_high =
  if low_value >= high_value then invalid_arg "low_value must be below high_value";
  if prior_high < 0.0 || prior_high > 1.0 || Float.is_nan prior_high then
    invalid_arg "prior_high must lie in [0, 1]";
  { low_value; high_value; prior_high }

let value_of_fundamental market = function
  | Low -> market.low_value
  | High -> market.high_value

let opposite_side = function Buy -> Sell | Sell -> Buy
let string_of_side = function Buy -> "buy" | Sell -> "sell"
let string_of_fundamental = function Low -> "low" | High -> "high"
let string_of_trader_kind = function Informed -> "informed" | Noise -> "noise"
