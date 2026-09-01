type config = {
  start_mid : float;
  step_count : int;
  volatility : float;
  half_spread : float;
  base_fill : float;
  fill_decay : float;
  inventory_skew : float;
}

type episode_summary = {
  terminal_wealth : float;
  final_inventory : int;
  max_abs_inventory : int;
  mean_abs_inventory : float;
  fill_count : int;
}

val quote_for_inventory :
  mid:float ->
  half_spread:float ->
  inventory_skew:float ->
  inventory_units:int ->
  Domain.quote

val fill_probability : base_fill:float -> fill_decay:float -> distance:float -> float
val run_episode : rng:Random.State.t -> config -> episode_summary
