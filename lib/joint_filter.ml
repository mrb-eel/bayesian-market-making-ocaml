open Domain

type t = {
  alpha_grid : float array;
  low_mass : float array;
  high_mass : float array;
}

let validate_inputs ~prior_high ~alpha_grid =
  if Array.length alpha_grid = 0 then invalid_arg "alpha_grid cannot be empty";
  if prior_high < 0.0 || prior_high > 1.0 || Float.is_nan prior_high then
    invalid_arg "prior_high must lie in [0, 1]";
  Array.iter
    (fun alpha ->
      if alpha < 0.0 || alpha > 1.0 || Float.is_nan alpha then
        invalid_arg "every alpha candidate must lie in [0, 1]")
    alpha_grid

let create ~prior_high ~alpha_grid =
  validate_inputs ~prior_high ~alpha_grid;
  let grid_size = float_of_int (Array.length alpha_grid) in
  {
    alpha_grid = Array.copy alpha_grid;
    low_mass = Array.make (Array.length alpha_grid) ((1.0 -. prior_high) /. grid_size);
    high_mass = Array.make (Array.length alpha_grid) (prior_high /. grid_size);
  }

let total_mass filter =
  Array.fold_left ( +. ) 0.0 filter.low_mass
  +. Array.fold_left ( +. ) 0.0 filter.high_mass

let from_order_counts ~prior_high ~alpha_grid ~buys ~sells =
  if buys < 0 || sells < 0 then invalid_arg "order counts cannot be negative";
  validate_inputs ~prior_high ~alpha_grid;
  let slots = Array.length alpha_grid in
  let low_mass = Array.make slots 0.0 in
  let high_mass = Array.make slots 0.0 in
  let prior_alpha = 1.0 /. float_of_int slots in
  let evidence = ref 0.0 in

  for alpha_slot = 0 to slots - 1 do
    let alpha = alpha_grid.(alpha_slot) in
    let buy_high = Binary_model.buy_chance ~alpha High in
    let buy_low = Binary_model.buy_chance ~alpha Low in
    let high_likelihood =
      (buy_high ** float_of_int buys) *. ((1.0 -. buy_high) ** float_of_int sells)
    in
    let low_likelihood =
      (buy_low ** float_of_int buys) *. ((1.0 -. buy_low) ** float_of_int sells)
    in
    let low_weight = (1.0 -. prior_high) *. prior_alpha *. low_likelihood in
    let high_weight = prior_high *. prior_alpha *. high_likelihood in
    low_mass.(alpha_slot) <- low_weight;
    high_mass.(alpha_slot) <- high_weight;
    evidence := !evidence +. low_weight +. high_weight
  done;

  if !evidence <= 0.0 then invalid_arg "joint posterior has zero evidence";
  for alpha_slot = 0 to slots - 1 do
    low_mass.(alpha_slot) <- low_mass.(alpha_slot) /. !evidence;
    high_mass.(alpha_slot) <- high_mass.(alpha_slot) /. !evidence
  done;
  { alpha_grid = Array.copy alpha_grid; low_mass; high_mass }

let update filter side =
  let slots = Array.length filter.alpha_grid in
  let next_low = Array.make slots 0.0 in
  let next_high = Array.make slots 0.0 in
  let evidence = ref 0.0 in
  for alpha_slot = 0 to slots - 1 do
    let alpha = filter.alpha_grid.(alpha_slot) in
    let low_weight =
      filter.low_mass.(alpha_slot)
      *. Binary_model.side_likelihood ~alpha ~fundamental:Low side
    in
    let high_weight =
      filter.high_mass.(alpha_slot)
      *. Binary_model.side_likelihood ~alpha ~fundamental:High side
    in
    next_low.(alpha_slot) <- low_weight;
    next_high.(alpha_slot) <- high_weight;
    evidence := !evidence +. low_weight +. high_weight
  done;
  if !evidence <= 0.0 then invalid_arg "joint posterior has zero evidence";
  for alpha_slot = 0 to slots - 1 do
    next_low.(alpha_slot) <- next_low.(alpha_slot) /. !evidence;
    next_high.(alpha_slot) <- next_high.(alpha_slot) /. !evidence
  done;
  { filter with low_mass = next_low; high_mass = next_high }

let posterior_high filter = Array.fold_left ( +. ) 0.0 filter.high_mass

let mean_alpha filter =
  let estimate = ref 0.0 in
  for alpha_slot = 0 to Array.length filter.alpha_grid - 1 do
    let state_mass = filter.low_mass.(alpha_slot) +. filter.high_mass.(alpha_slot) in
    estimate := !estimate +. (filter.alpha_grid.(alpha_slot) *. state_mass)
  done;
  !estimate

let side_conditioned_value market filter side =
  let weighted_value = ref 0.0 in
  let side_evidence = ref 0.0 in
  for alpha_slot = 0 to Array.length filter.alpha_grid - 1 do
    let alpha = filter.alpha_grid.(alpha_slot) in
    let low_evidence =
      filter.low_mass.(alpha_slot)
      *. Binary_model.side_likelihood ~alpha ~fundamental:Low side
    in
    let high_evidence =
      filter.high_mass.(alpha_slot)
      *. Binary_model.side_likelihood ~alpha ~fundamental:High side
    in
    side_evidence := !side_evidence +. low_evidence +. high_evidence;
    weighted_value :=
      !weighted_value
      +. (market.low_value *. low_evidence)
      +. (market.high_value *. high_evidence)
  done;
  if !side_evidence <= 0.0 then invalid_arg "cannot quote an impossible side";
  !weighted_value /. !side_evidence

let quote market filter =
  let bid = side_conditioned_value market filter Sell in
  let ask = side_conditioned_value market filter Buy in
  { bid; ask }
