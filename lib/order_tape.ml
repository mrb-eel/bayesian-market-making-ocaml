open Domain

type arrival = {
  trader_kind : trader_kind;
  side : side;
}

type t = {
  fundamental : fundamental;
  arrivals : arrival array;
}

let draw_fundamental rng = if Random_tools.bernoulli rng 0.5 then High else Low

let draw_trader_kind rng ~alpha =
  if Random_tools.bernoulli rng alpha then Informed else Noise

let draw_side rng ~fundamental ~trader_kind =
  match trader_kind with
  | Informed -> (match fundamental with High -> Buy | Low -> Sell)
  | Noise -> if Random_tools.bernoulli rng 0.5 then Buy else Sell

let hidden_value_or_draw rng = function
  | Some known_value -> known_value
  | None -> draw_fundamental rng

let build_arrivals ~rng ~hidden_value ~trade_count ~alpha_at =
  Array.init trade_count (fun trade_slot ->
      let trader_kind = draw_trader_kind rng ~alpha:(alpha_at trade_slot) in
      let side = draw_side rng ~fundamental:hidden_value ~trader_kind in
      { trader_kind; side })

let generate ?fundamental ~rng ~alpha ~trade_count () =
  if trade_count < 0 then invalid_arg "trade_count cannot be negative";
  let hidden_value = hidden_value_or_draw rng fundamental in
  let arrivals =
    build_arrivals ~rng ~hidden_value ~trade_count ~alpha_at:(fun _trade_slot -> alpha)
  in
  { fundamental = hidden_value; arrivals }

let generate_regime ?fundamental ~rng ~alpha_before ~alpha_after ~switch_after
    ~trade_count () =
  if trade_count < 0 then invalid_arg "trade_count cannot be negative";
  if switch_after < 0 || switch_after > trade_count then
    invalid_arg "switch_after must lie between zero and trade_count";
  let hidden_value = hidden_value_or_draw rng fundamental in
  let alpha_at trade_slot =
    if trade_slot < switch_after then alpha_before else alpha_after
  in
  let arrivals = build_arrivals ~rng ~hidden_value ~trade_count ~alpha_at in
  { fundamental = hidden_value; arrivals }
