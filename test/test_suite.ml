open Market_maker
open Domain
open Order_tape

let failures = ref []
let fail message = raise (Failure message)

let check_close ?(tolerance = 1e-9) label expected actual =
  if Float.is_nan actual || abs_float (expected -. actual) > tolerance then
    fail (Printf.sprintf "%s: expected %.12g, got %.12g" label expected actual)

let check_int label expected actual =
  if expected <> actual then
    fail (Printf.sprintf "%s: expected %d, got %d" label expected actual)

let check_bool label condition = if not condition then fail label

let check_invalid_argument label thunk =
  match thunk () with
  | _ -> fail (label ^ ": expected Invalid_argument")
  | exception Invalid_argument _ -> ()

let run_test name test_body =
  try
    test_body ();
    Printf.printf "ok  %s\n%!" name
  with exn ->
    let message = Printexc.to_string exn in
    failures := (name, message) :: !failures;
    Printf.eprintf "FAIL %s -- %s\n%!" name message

let market =
  Domain.make_market ~low_value:90.0 ~high_value:110.0 ~prior_high:0.5

let () =
  run_test "buy likelihoods" (fun () ->
      check_close "P(buy|high)" 0.6
        (Binary_model.buy_chance ~alpha:0.2 High);
      check_close "P(buy|low)" 0.4
        (Binary_model.buy_chance ~alpha:0.2 Low));

  run_test "posterior after a buy and sell" (fun () ->
      check_close "P(high|buy)" 0.6
        (Binary_model.posterior_high ~prior_high:0.5 ~alpha:0.2 Buy);
      check_close "P(high|sell)" 0.4
        (Binary_model.posterior_high ~prior_high:0.5 ~alpha:0.2 Sell));

  run_test "competitive quote is 98 / 102" (fun () ->
      let quote =
        Binary_model.competitive_quote market ~prior_high:0.5 ~alpha:0.2
      in
      check_close "bid" 98.0 quote.bid;
      check_close "ask" 102.0 quote.ask;
      check_close "spread" 4.0 (quote.ask -. quote.bid));

  run_test "zero informed flow gives a zero informational spread" (fun () ->
      let quote =
        Binary_model.competitive_quote market ~prior_high:0.5 ~alpha:0.0
      in
      check_close "bid" 100.0 quote.bid;
      check_close "ask" 100.0 quote.ask);

  run_test "buy then sell returns to the symmetric prior" (fun () ->
      let after_buy =
        Binary_model.posterior_high ~prior_high:0.5 ~alpha:0.2 Buy
      in
      let after_sell =
        Binary_model.posterior_high ~prior_high:after_buy ~alpha:0.2 Sell
      in
      check_close "posterior" 0.5 after_sell);

  run_test "spread follows the closed form away from the demo point" (fun () ->
      let quote =
        Binary_model.competitive_quote market ~prior_high:0.5 ~alpha:0.4
      in
      check_close "spread" 8.0 (quote.ask -. quote.bid));

  run_test "count-form posterior matches sequential Bayes" (fun () ->
      let from_counts =
        Binary_model.posterior_from_order_counts ~prior_high:0.5 ~alpha:0.2
          ~buys:3 ~sells:1
      in
      let sequential =
        [ Buy; Buy; Sell; Buy ]
        |> List.fold_left
             (fun posterior side ->
               Binary_model.posterior_high ~prior_high:posterior ~alpha:0.2
                 side)
             0.5
      in
      check_close "posterior" sequential from_counts);

  run_test "uninformative orders leave the prior unchanged" (fun () ->
      check_close "posterior" 0.37
        (Binary_model.posterior_from_order_counts ~prior_high:0.37 ~alpha:0.0
           ~buys:18 ~sells:3));

  run_test "invalid probabilities are rejected" (fun () ->
      check_invalid_argument "alpha above one" (fun () ->
          Binary_model.buy_chance ~alpha:1.1 High);
      check_invalid_argument "negative prior" (fun () ->
          Binary_model.posterior_high ~prior_high:(-0.1) ~alpha:0.2 Buy));

  run_test "static stays frozen; Bayesian moves" (fun () ->
      let static = Strategy.static ~prior_high:0.5 ~assumed_alpha:0.2 in
      let bayesian = Strategy.bayesian ~prior_high:0.5 ~assumed_alpha:0.2 in
      check_close "static" 0.5
        (Strategy.observe static Buy |> Strategy.belief_high);
      check_close "bayesian" 0.6
        (Strategy.observe bayesian Buy |> Strategy.belief_high));

  run_test "joint posterior remains normalised" (fun () ->
      let filter =
        Joint_filter.create ~prior_high:0.5 ~alpha_grid:[| 0.1; 0.2; 0.4 |]
      in
      let updated =
        Joint_filter.update filter Buy |> fun next ->
        Joint_filter.update next Buy
      in
      check_close "mass" 1.0 (Joint_filter.total_mass updated);
      check_bool "posterior should favour high"
        (Joint_filter.posterior_high updated > 0.5));

  run_test "joint count constructor matches sequential updates" (fun () ->
      let grid = [| 0.1; 0.2; 0.4 |] in
      let sequential =
        [ Buy; Buy; Sell ]
        |> List.fold_left Joint_filter.update
             (Joint_filter.create ~prior_high:0.5 ~alpha_grid:grid)
      in
      let counted =
        Joint_filter.from_order_counts ~prior_high:0.5 ~alpha_grid:grid
          ~buys:2 ~sells:1
      in
      check_close "state posterior" (Joint_filter.posterior_high sequential)
        (Joint_filter.posterior_high counted);
      check_close "alpha posterior" (Joint_filter.mean_alpha sequential)
        (Joint_filter.mean_alpha counted));

  run_test "joint quote remains two-sided" (fun () ->
      let filter =
        Joint_filter.create ~prior_high:0.5 ~alpha_grid:[| 0.1; 0.2; 0.4 |]
        |> fun current -> Joint_filter.update current Buy
      in
      let quote = Joint_filter.quote market filter in
      check_bool "bid should not exceed ask" (quote.bid <= quote.ask));

  run_test "rolling filter actually expires old observations" (fun () ->
      let filter =
        Rolling_filter.create ~prior_high:0.5 ~alpha_grid:[| 0.2 |]
          ~window:2
        |> fun current -> Rolling_filter.update current Buy
        |> fun current -> Rolling_filter.update current Buy
        |> fun current -> Rolling_filter.update current Sell
      in
      check_int "window size" 2 (Rolling_filter.observation_count filter);
      check_close "latest buy and sell cancel" 0.5
        (Rolling_filter.posterior_high filter));

  run_test "cash and inventory signs are from the market maker's side" (fun () ->
      let quote = { bid = 98.0; ask = 102.0 } in
      let after_customer_buy =
        Information_sim.execute_fill Information_sim.empty_account
          ~customer_side:Buy quote
      in
      check_int "inventory after customer buy" (-1)
        after_customer_buy.inventory_units;
      check_close "cash after customer buy" 102.0
        after_customer_buy.cash_balance;
      check_close "settled buy pnl" (-8.0)
        (Information_sim.settle after_customer_buy ~terminal_value:110.0);
      check_close "buy trade pnl" (-8.0)
        (Information_sim.economic_trade_pnl ~terminal_value:110.0
           ~customer_side:Buy quote);

      let after_customer_sell =
        Information_sim.execute_fill Information_sim.empty_account
          ~customer_side:Sell quote
      in
      check_int "inventory after customer sell" 1
        after_customer_sell.inventory_units;
      check_close "cash after customer sell" (-98.0)
        after_customer_sell.cash_balance;
      check_close "settled sell pnl" 12.0
        (Information_sim.settle after_customer_sell ~terminal_value:110.0);
      check_close "sell trade pnl" 12.0
        (Information_sim.economic_trade_pnl ~terminal_value:110.0
           ~customer_side:Sell quote));

  run_test "episode wealth agrees with trade-level economics" (fun () ->
      let tape : Order_tape.t =
        {
          fundamental = High;
          arrivals =
            [|
              ({ trader_kind = Noise; side = Buy } : Order_tape.arrival);
              ({ trader_kind = Noise; side = Sell } : Order_tape.arrival);
              ({ trader_kind = Informed; side = Buy } : Order_tape.arrival);
            |];
        }
      in
      let episode =
        Information_sim.run ~market ~tape
          ~starting_strategy:
            (Strategy.static ~prior_high:0.5 ~assumed_alpha:0.2)
          ~keep_trace:false
      in
      check_close "pnl attribution"
        episode.terminal_wealth
        (episode.noise_flow_pnl +. episode.informed_flow_pnl));

  run_test "an empty episode settles flat" (fun () ->
      let tape : Order_tape.t = { fundamental = Low; arrivals = [||] } in
      let episode =
        Information_sim.run ~market ~tape
          ~starting_strategy:
            (Strategy.bayesian ~prior_high:0.5 ~assumed_alpha:0.2)
          ~keep_trace:true
      in
      check_close "wealth" 0.0 episode.terminal_wealth;
      check_close "rmse" 0.0 episode.fair_value_rmse;
      check_int "inventory" 0 episode.final_inventory;
      match episode.trace with
      | Some trace -> check_int "trace length" 0 (Array.length trace)
      | None -> fail "trace should be present");

  run_test "scenario generation is reproducible" (fun () ->
      let first =
        Order_tape.generate ~rng:(Random.State.make [| 42 |]) ~alpha:0.2
          ~trade_count:20 ()
      in
      let second =
        Order_tape.generate ~rng:(Random.State.make [| 42 |]) ~alpha:0.2
          ~trade_count:20 ()
      in
      check_bool "fundamental" (first.fundamental = second.fundamental);
      check_bool "arrivals" (first.arrivals = second.arrivals));

  run_test "regime generator changes trader prevalence at the switch" (fun () ->
      let tape =
        Order_tape.generate_regime ~fundamental:High
          ~rng:(Random.State.make [| 73 |]) ~alpha_before:0.0 ~alpha_after:1.0
          ~switch_after:4 ~trade_count:9 ()
      in
      for trade_slot = 0 to 3 do
        check_bool "pre-switch trader should be noise"
          (tape.arrivals.(trade_slot).trader_kind = Noise)
      done;
      for trade_slot = 4 to 8 do
        check_bool "post-switch trader should be informed"
          (tape.arrivals.(trade_slot).trader_kind = Informed);
        check_bool "informed trader should buy high value"
          (tape.arrivals.(trade_slot).side = Buy)
      done);

  run_test "inventory skew moves quotes toward liquidation" (fun () ->
      let flat =
        Inventory_sim.quote_for_inventory ~mid:100.0 ~half_spread:1.0
          ~inventory_skew:0.1 ~inventory_units:0
      in
      let long =
        Inventory_sim.quote_for_inventory ~mid:100.0 ~half_spread:1.0
          ~inventory_skew:0.1 ~inventory_units:8
      in
      let short =
        Inventory_sim.quote_for_inventory ~mid:100.0 ~half_spread:1.0
          ~inventory_skew:0.1 ~inventory_units:(-8)
      in
      check_bool "long bid moves down" (long.bid < flat.bid);
      check_bool "long ask moves down" (long.ask < flat.ask);
      check_bool "short bid moves up" (short.bid > flat.bid);
      check_bool "short ask moves up" (short.ask > flat.ask));

  run_test "fill probability falls with quote distance" (fun () ->
      let near =
        Inventory_sim.fill_probability ~base_fill:0.8 ~fill_decay:1.1
          ~distance:0.2
      in
      let far =
        Inventory_sim.fill_probability ~base_fill:0.8 ~fill_decay:1.1
          ~distance:2.0
      in
      check_bool "near quote should fill more often" (near > far);
      check_bool "probability stays bounded" (near >= 0.0 && near <= 1.0));

  run_test "inventory episodes are reproducible" (fun () ->
      let config : Inventory_sim.config =
        {
          start_mid = 100.0;
          step_count = 30;
          volatility = 0.45;
          half_spread = 0.75;
          base_fill = 0.8;
          fill_decay = 1.1;
          inventory_skew = 0.1;
        }
      in
      let first =
        Inventory_sim.run_episode ~rng:(Random.State.make [| 99 |]) config
      in
      let second =
        Inventory_sim.run_episode ~rng:(Random.State.make [| 99 |]) config
      in
      check_bool "same seed should give the same episode" (first = second));

  run_test "sample statistics and quantiles" (fun () ->
      let observations = [| 1.0; 2.0; 3.0; 4.0 |] in
      check_close "mean" 2.5 (Stats.mean observations);
      check_close "median" 2.5 (Stats.quantile 0.5 observations);
      check_close "sample variance" (5.0 /. 3.0)
        (Stats.variance observations));

  match List.rev !failures with
  | [] -> Printf.printf "\nAll %d tests passed.\n%!" 23
  | failed ->
      Printf.eprintf "\n%d test(s) failed:\n" (List.length failed);
      List.iter
        (fun (name, message) -> Printf.eprintf "- %s: %s\n" name message)
        failed;
      exit 1
