open Domain

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

let quote_for_inventory ~mid ~half_spread ~inventory_skew ~inventory_units =
  if half_spread <= 0.0 then invalid_arg "half_spread must be positive";
  let reservation_price =
    mid -. (inventory_skew *. float_of_int inventory_units)
  in
  { bid = reservation_price -. half_spread; ask = reservation_price +. half_spread }

let fill_probability ~base_fill ~fill_decay ~distance =
  if base_fill < 0.0 || base_fill > 1.0 then invalid_arg "base_fill must lie in [0, 1]";
  if fill_decay < 0.0 then invalid_arg "fill_decay cannot be negative";
  let quote_distance = max 0.0 distance in
  min 1.0 (base_fill *. exp (-. fill_decay *. quote_distance))

let run_episode ~rng config =
  if config.step_count < 0 then invalid_arg "step_count cannot be negative";
  if config.volatility < 0.0 then invalid_arg "volatility cannot be negative";

  let live_mid = ref config.start_mid in
  let cash_balance = ref 0.0 in
  let inventory_units = ref 0 in
  let max_abs_inventory = ref 0 in
  let absolute_inventory_total = ref 0.0 in
  let fill_count = ref 0 in

  for _market_step = 1 to config.step_count do
    let live_quote =
      quote_for_inventory ~mid:!live_mid ~half_spread:config.half_spread
        ~inventory_skew:config.inventory_skew ~inventory_units:!inventory_units
    in
    let customer_side = if Random_tools.bernoulli rng 0.5 then Buy else Sell in
    let distance =
      match customer_side with
      | Buy -> live_quote.ask -. !live_mid
      | Sell -> !live_mid -. live_quote.bid
    in
    let fill_chance =
      fill_probability ~base_fill:config.base_fill ~fill_decay:config.fill_decay ~distance
    in
    let got_filled = Random_tools.bernoulli rng fill_chance in

    if got_filled then (
      incr fill_count;
      match customer_side with
      | Buy ->
          cash_balance := !cash_balance +. live_quote.ask;
          decr inventory_units
      | Sell ->
          cash_balance := !cash_balance -. live_quote.bid;
          incr inventory_units);

    max_abs_inventory := max !max_abs_inventory (abs !inventory_units);
    absolute_inventory_total :=
      !absolute_inventory_total +. float_of_int (abs !inventory_units);
    live_mid := !live_mid +. (config.volatility *. Random_tools.standard_normal rng)
  done;

  let mean_abs_inventory =
    if config.step_count = 0 then 0.0
    else !absolute_inventory_total /. float_of_int config.step_count
  in
  {
    terminal_wealth =
      !cash_balance +. (float_of_int !inventory_units *. !live_mid);
    final_inventory = !inventory_units;
    max_abs_inventory = !max_abs_inventory;
    mean_abs_inventory;
    fill_count = !fill_count;
  }
