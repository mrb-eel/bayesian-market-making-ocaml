type account = {
  cash_balance : float;
  inventory_units : int;
}

type trace_point = {
  trade_no : int;
  customer_side : Domain.side;
  trader_kind : Domain.trader_kind;
  bid : float;
  ask : float;
  belief_high_before : float;
  belief_high_after : float;
  fair_value_before : float;
  cash_after : float;
  inventory_after : int;
}

type episode_summary = {
  terminal_wealth : float;
  final_inventory : int;
  max_abs_inventory : int;
  fair_value_rmse : float;
  informed_flow_pnl : float;
  noise_flow_pnl : float;
  mean_quoted_spread : float;
  final_alpha_estimate : float;
  trace : trace_point array option;
}

val empty_account : account
val execute_fill : account -> customer_side:Domain.side -> Domain.quote -> account
val settle : account -> terminal_value:float -> float

val economic_trade_pnl :
  terminal_value:float -> customer_side:Domain.side -> Domain.quote -> float

val run :
  market:Domain.market ->
  tape:Order_tape.t ->
  starting_strategy:Strategy.t ->
  keep_trace:bool ->
  episode_summary
