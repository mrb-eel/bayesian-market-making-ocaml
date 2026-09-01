open Domain

type t = {
  prior_high : float;
  alpha_grid : float array;
  window : int;
  newest_first : side list;
  buy_count : int;
  sell_count : int;
  posterior : Joint_filter.t;
}

let create ~prior_high ~alpha_grid ~window =
  if window <= 0 then invalid_arg "rolling window must be positive";
  {
    prior_high;
    alpha_grid = Array.copy alpha_grid;
    window;
    newest_first = [];
    buy_count = 0;
    sell_count = 0;
    posterior = Joint_filter.create ~prior_high ~alpha_grid;
  }

let rec remove_oldest = function
  | [] -> invalid_arg "cannot remove an observation from an empty window"
  | [ oldest ] -> ([], oldest)
  | newest :: older ->
      let kept, oldest = remove_oldest older in
      (newest :: kept, oldest)

let count_side side ~buy_count ~sell_count delta =
  match side with
  | Buy -> (buy_count + delta, sell_count)
  | Sell -> (buy_count, sell_count + delta)

let update filter side =
  let observations = side :: filter.newest_first in
  let buy_count, sell_count =
    count_side side ~buy_count:filter.buy_count ~sell_count:filter.sell_count 1
  in
  let newest_first, buy_count, sell_count =
    if List.length observations <= filter.window then
      (observations, buy_count, sell_count)
    else
      let kept, expired = remove_oldest observations in
      let buys, sells = count_side expired ~buy_count ~sell_count (-1) in
      (kept, buys, sells)
  in
  let posterior =
    Joint_filter.from_order_counts ~prior_high:filter.prior_high
      ~alpha_grid:filter.alpha_grid ~buys:buy_count ~sells:sell_count
  in
  { filter with newest_first; buy_count; sell_count; posterior }

let posterior_high filter = Joint_filter.posterior_high filter.posterior
let mean_alpha filter = Joint_filter.mean_alpha filter.posterior
let quote market filter = Joint_filter.quote market filter.posterior
let observation_count filter = filter.buy_count + filter.sell_count
