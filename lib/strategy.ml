type t =
  | Static of {
      frozen_high : float;
      assumed_alpha : float;
    }
  | Bayesian of {
      posterior_high : float;
      assumed_alpha : float;
    }
  | Joint of Joint_filter.t
  | Rolling_joint of Rolling_filter.t

let static ~prior_high ~assumed_alpha = Static { frozen_high = prior_high; assumed_alpha }

let bayesian ~prior_high ~assumed_alpha =
  Bayesian { posterior_high = prior_high; assumed_alpha }

let joint ~prior_high ~alpha_grid = Joint (Joint_filter.create ~prior_high ~alpha_grid)

let rolling_joint ~prior_high ~alpha_grid ~window =
  Rolling_joint (Rolling_filter.create ~prior_high ~alpha_grid ~window)

let label = function
  | Static _ -> "static"
  | Bayesian _ -> "bayesian"
  | Joint _ -> "joint-bayes"
  | Rolling_joint _ -> "rolling-joint"

let belief_high = function
  | Static state -> state.frozen_high
  | Bayesian state -> state.posterior_high
  | Joint filter -> Joint_filter.posterior_high filter
  | Rolling_joint filter -> Rolling_filter.posterior_high filter

let alpha_estimate = function
  | Static state -> state.assumed_alpha
  | Bayesian state -> state.assumed_alpha
  | Joint filter -> Joint_filter.mean_alpha filter
  | Rolling_joint filter -> Rolling_filter.mean_alpha filter

let quote market = function
  | Static state ->
      Binary_model.competitive_quote market ~prior_high:state.frozen_high
        ~alpha:state.assumed_alpha
  | Bayesian state ->
      Binary_model.competitive_quote market ~prior_high:state.posterior_high
        ~alpha:state.assumed_alpha
  | Joint filter -> Joint_filter.quote market filter
  | Rolling_joint filter -> Rolling_filter.quote market filter

let observe strategy side =
  match strategy with
  | Static _ -> strategy
  | Bayesian state ->
      let posterior_high =
        Binary_model.posterior_high ~prior_high:state.posterior_high
          ~alpha:state.assumed_alpha side
      in
      Bayesian { state with posterior_high }
  | Joint filter -> Joint (Joint_filter.update filter side)
  | Rolling_joint filter -> Rolling_joint (Rolling_filter.update filter side)
