open Domain
open Order_tape

type account = {
  cash_balance : float;
  inventory_units : int;
}

type trace_point = {
  trade_no : int;
  customer_side : side;
  trader_kind : trader_kind;
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

let empty_account = { cash_balance = 0.0; inventory_units = 0 }

let execute_fill account ~customer_side quote =
  match customer_side with
  | Buy ->
      {
        cash_balance = account.cash_balance +. quote.ask;
        inventory_units = account.inventory_units - 1;
      }
  | Sell ->
      {
        cash_balance = account.cash_balance -. quote.bid;
        inventory_units = account.inventory_units + 1;
      }

let settle account ~terminal_value =
  account.cash_balance +. (float_of_int account.inventory_units *. terminal_value)

let economic_trade_pnl ~terminal_value ~customer_side quote =
  match customer_side with
  | Buy -> quote.ask -. terminal_value
  | Sell -> terminal_value -. quote.bid

let run ~market ~tape ~starting_strategy ~keep_trace =
  let terminal_value = Domain.value_of_fundamental market tape.fundamental in
  let live_account = ref empty_account in
  let active_strategy = ref starting_strategy in
  let squared_error_pile = ref 0.0 in
  let informed_flow_pnl = ref 0.0 in
  let noise_flow_pnl = ref 0.0 in
  let spread_total = ref 0.0 in
  let max_abs_inventory = ref 0 in
  let trace_backwards = ref [] in

  Array.iteri
    (fun trade_slot arrival ->
      let belief_before = Strategy.belief_high !active_strategy in
      let fair_before = Binary_model.fair_value market belief_before in
      let live_quote = Strategy.quote market !active_strategy in
      let per_trade_pnl =
        economic_trade_pnl ~terminal_value ~customer_side:arrival.side live_quote
      in

      squared_error_pile :=
        !squared_error_pile +. ((fair_before -. terminal_value) ** 2.0);
      spread_total := !spread_total +. (live_quote.ask -. live_quote.bid);
      (match arrival.trader_kind with
      | Informed -> informed_flow_pnl := !informed_flow_pnl +. per_trade_pnl
      | Noise -> noise_flow_pnl := !noise_flow_pnl +. per_trade_pnl);

      let account_after_fill =
        execute_fill !live_account ~customer_side:arrival.side live_quote
      in
      let strategy_after_trade = Strategy.observe !active_strategy arrival.side in
      live_account := account_after_fill;
      active_strategy := strategy_after_trade;
      max_abs_inventory :=
        max !max_abs_inventory (abs account_after_fill.inventory_units);

      if keep_trace then
        trace_backwards :=
          {
            trade_no = trade_slot + 1;
            customer_side = arrival.side;
            trader_kind = arrival.trader_kind;
            bid = live_quote.bid;
            ask = live_quote.ask;
            belief_high_before = belief_before;
            belief_high_after = Strategy.belief_high strategy_after_trade;
            fair_value_before = fair_before;
            cash_after = account_after_fill.cash_balance;
            inventory_after = account_after_fill.inventory_units;
          }
          :: !trace_backwards)
    tape.arrivals;

  let trade_count = Array.length tape.arrivals in
  let fair_value_rmse =
    if trade_count = 0 then 0.0
    else sqrt (!squared_error_pile /. float_of_int trade_count)
  in
  let mean_quoted_spread =
    if trade_count = 0 then 0.0 else !spread_total /. float_of_int trade_count
  in
  let trace =
    if keep_trace then Some (Array.of_list (List.rev !trace_backwards)) else None
  in
  let final_account = !live_account in
  {
    terminal_wealth = settle final_account ~terminal_value;
    final_inventory = final_account.inventory_units;
    max_abs_inventory = !max_abs_inventory;
    fair_value_rmse;
    informed_flow_pnl = !informed_flow_pnl;
    noise_flow_pnl = !noise_flow_pnl;
    mean_quoted_spread;
    final_alpha_estimate = Strategy.alpha_estimate !active_strategy;
    trace;
  }
