type arrival = {
  trader_kind : Domain.trader_kind;
  side : Domain.side;
}

type t = {
  fundamental : Domain.fundamental;
  arrivals : arrival array;
}

val generate :
  ?fundamental:Domain.fundamental ->
  rng:Random.State.t ->
  alpha:float ->
  trade_count:int ->
  unit ->
  t

val generate_regime :
  ?fundamental:Domain.fundamental ->
  rng:Random.State.t ->
  alpha_before:float ->
  alpha_after:float ->
  switch_after:int ->
  trade_count:int ->
  unit ->
  t
