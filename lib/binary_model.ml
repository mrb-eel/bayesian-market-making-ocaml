open Domain

let validate_probability label chance =
  if chance < 0.0 || chance > 1.0 || Float.is_nan chance then
    invalid_arg (Printf.sprintf "%s must lie in [0, 1]" label)

let buy_chance ~alpha fundamental =
  validate_probability "alpha" alpha;
  match fundamental with
  | High -> (1.0 +. alpha) /. 2.0
  | Low -> (1.0 -. alpha) /. 2.0

let side_likelihood ~alpha ~fundamental side =
  let chance_of_buy = buy_chance ~alpha fundamental in
  match side with Buy -> chance_of_buy | Sell -> 1.0 -. chance_of_buy

let posterior_high ~prior_high ~alpha side =
  validate_probability "prior_high" prior_high;
  let high_likelihood = side_likelihood ~alpha ~fundamental:High side in
  let low_likelihood = side_likelihood ~alpha ~fundamental:Low side in
  let high_mass = prior_high *. high_likelihood in
  let low_mass = (1.0 -. prior_high) *. low_likelihood in
  let evidence = high_mass +. low_mass in
  if evidence <= 0.0 then invalid_arg "the observed side has zero model probability";
  high_mass /. evidence

let fair_value market probability_high =
  validate_probability "probability_high" probability_high;
  (probability_high *. market.high_value)
  +. ((1.0 -. probability_high) *. market.low_value)

let conditional_value market ~prior_high ~alpha side =
  posterior_high ~prior_high ~alpha side |> fair_value market

let competitive_quote market ~prior_high ~alpha =
  let bid = conditional_value market ~prior_high ~alpha Sell in
  let ask = conditional_value market ~prior_high ~alpha Buy in
  { bid; ask }

let log_odds chance =
  validate_probability "chance" chance;
  if chance = 0.0 then neg_infinity
  else if chance = 1.0 then infinity
  else log (chance /. (1.0 -. chance))

let probability_from_log_odds odds =
  if odds >= 0.0 then
    let shrink = exp (-. odds) in
    1.0 /. (1.0 +. shrink)
  else
    let growth = exp odds in
    growth /. (1.0 +. growth)

let posterior_from_order_counts ~prior_high ~alpha ~buys ~sells =
  if buys < 0 || sells < 0 then invalid_arg "order counts cannot be negative";
  validate_probability "prior_high" prior_high;
  validate_probability "alpha" alpha;
  if alpha = 1.0 then
    (* The closed form becomes infinite; sequential updating keeps the edge cases honest. *)
    let posterior = ref prior_high in
    for _buy_no = 1 to buys do
      posterior := posterior_high ~prior_high:!posterior ~alpha Buy
    done;
    for _sell_no = 1 to sells do
      posterior := posterior_high ~prior_high:!posterior ~alpha Sell
    done;
    !posterior
  else
    let order_imbalance = float_of_int (buys - sells) in
    let evidence_per_buy = log ((1.0 +. alpha) /. (1.0 -. alpha)) in
    probability_from_log_odds (log_odds prior_high +. (order_imbalance *. evidence_per_buy))
