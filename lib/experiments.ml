open Domain
open Order_tape

type workload = {
  spread_trials : int;
  discovery_paths : int;
  strategy_episodes : int;
  misspec_episodes : int;
  unknown_alpha_episodes : int;
  inventory_episodes : int;
  regime_paths : int;
  information_trades : int;
  discovery_trades : int;
  inventory_steps : int;
  regime_trades : int;
}

type strategy_run = {
  strategy_name : string;
  pnl_samples : float array;
  rmse_samples : float array;
  informed_pnl_samples : float array;
  noise_pnl_samples : float array;
  spread_samples : float array;
  alpha_estimates : float array;
}

let workload ~quick =
  if quick then
    {
      spread_trials = 5_000;
      discovery_paths = 250;
      strategy_episodes = 350;
      misspec_episodes = 120;
      unknown_alpha_episodes = 180;
      inventory_episodes = 250;
      regime_paths = 80;
      information_trades = 30;
      discovery_trades = 45;
      inventory_steps = 90;
      regime_trades = 120;
    }
  else
    {
      spread_trials = 100_000;
      discovery_paths = 3_000;
      strategy_episodes = 6_000;
      misspec_episodes = 1_800;
      unknown_alpha_episodes = 2_500;
      inventory_episodes = 3_500;
      regime_paths = 800;
      information_trades = 60;
      discovery_trades = 80;
      inventory_steps = 300;
      regime_trades = 200;
    }

let baseline_market =
  Domain.make_market ~low_value:90.0 ~high_value:110.0 ~prior_high:0.5

let alpha_grid =
  [| 0.0; 0.05; 0.10; 0.15; 0.20; 0.25; 0.30; 0.35; 0.40; 0.45; 0.50 |]

let study_alphas = [| 0.05; 0.10; 0.20; 0.30; 0.40; 0.50 |]
let output_path output_dir filename = Filename.concat output_dir filename
let float_cell = Csv_writer.float_cell
let int_cell = Csv_writer.int_cell

let spread_validation ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let rng = Random_tools.seeded ~seed ~salt:101 in
  let csv_rows =
    ref
      [
        [
          "alpha";
          "theoretical_bid";
          "theoretical_ask";
          "theoretical_spread";
          "simulated_bid";
          "simulated_ask";
          "simulated_spread";
          "buy_count";
          "sell_count";
        ];
      ]
  in
  let conditional_mean label running_total observation_count =
    if observation_count = 0 then
      failwith (Printf.sprintf "spread validation saw no %s observations" label);
    running_total /. float_of_int observation_count
  in

  Array.iter
    (fun alpha ->
      let buy_value_total = ref 0.0 in
      let sell_value_total = ref 0.0 in
      let buy_count = ref 0 in
      let sell_count = ref 0 in
      for _trial_no = 1 to run_size.spread_trials do
        let tape = Order_tape.generate ~rng ~alpha ~trade_count:1 () in
        let hidden_value =
          Domain.value_of_fundamental baseline_market tape.fundamental
        in
        match tape.arrivals.(0).side with
        | Buy ->
            incr buy_count;
            buy_value_total := !buy_value_total +. hidden_value
        | Sell ->
            incr sell_count;
            sell_value_total := !sell_value_total +. hidden_value
      done;
      let simulated_ask = conditional_mean "buy" !buy_value_total !buy_count in
      let simulated_bid = conditional_mean "sell" !sell_value_total !sell_count in
      let theoretical_quote =
        Binary_model.competitive_quote baseline_market ~prior_high:0.5 ~alpha
      in
      csv_rows :=
        [
          float_cell alpha;
          float_cell theoretical_quote.bid;
          float_cell theoretical_quote.ask;
          float_cell (theoretical_quote.ask -. theoretical_quote.bid);
          float_cell simulated_bid;
          float_cell simulated_ask;
          float_cell (simulated_ask -. simulated_bid);
          int_cell !buy_count;
          int_cell !sell_count;
        ]
        :: !csv_rows)
    alpha_grid;

  Csv_writer.write (output_path output_dir "spread_validation.csv")
    (List.rev !csv_rows)

let price_discovery ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let rng = Random_tools.seeded ~seed ~salt:202 in
  let path_rows =
    ref
      [
        [
          "alpha";
          "trade_no";
          "q25_correct_confidence";
          "median_correct_confidence";
          "q75_correct_confidence";
        ];
      ]
  in
  let hitting_rows =
    ref
      [
        [
          "alpha";
          "threshold";
          "reach_rate";
          "mean_hitting_time";
          "median_hitting_time";
        ];
      ]
  in
  let thresholds = [| 0.90; 0.95; 0.99 |] in

  Array.iter
    (fun alpha ->
      let confidence_by_trade =
        Array.init (run_size.discovery_trades + 1) (fun _trade_no ->
            Array.make run_size.discovery_paths 0.0)
      in
      let hitting_times =
        Array.init (Array.length thresholds) (fun _threshold_slot ->
            Array.make run_size.discovery_paths (-1))
      in

      for path_no = 0 to run_size.discovery_paths - 1 do
        let tape =
          Order_tape.generate ~rng ~alpha ~trade_count:run_size.discovery_trades ()
        in
        let posterior_high = ref baseline_market.prior_high in
        let correct_confidence () =
          match tape.fundamental with
          | High -> !posterior_high
          | Low -> 1.0 -. !posterior_high
        in
        confidence_by_trade.(0).(path_no) <- correct_confidence ();
        Array.iteri
          (fun trade_slot arrival ->
            posterior_high :=
              Binary_model.posterior_high ~prior_high:!posterior_high ~alpha
                arrival.side;
            let confidence = correct_confidence () in
            confidence_by_trade.(trade_slot + 1).(path_no) <- confidence;
            Array.iteri
              (fun threshold_slot threshold ->
                if
                  hitting_times.(threshold_slot).(path_no) = -1
                  && confidence >= threshold
                then hitting_times.(threshold_slot).(path_no) <- trade_slot + 1)
              thresholds)
          tape.arrivals
      done;

      Array.iteri
        (fun trade_no confidence_slice ->
          path_rows :=
            [
              float_cell alpha;
              int_cell trade_no;
              float_cell (Stats.quantile 0.25 confidence_slice);
              float_cell (Stats.quantile 0.50 confidence_slice);
              float_cell (Stats.quantile 0.75 confidence_slice);
            ]
            :: !path_rows)
        confidence_by_trade;

      Array.iteri
        (fun threshold_slot threshold ->
          let reached =
            hitting_times.(threshold_slot)
            |> Array.to_list
            |> List.filter (fun trade_no -> trade_no >= 0)
            |> Array.of_list
          in
          let reach_rate =
            float_of_int (Array.length reached)
            /. float_of_int run_size.discovery_paths
          in
          let mean_hitting =
            if Array.length reached = 0 then nan else Stats.mean_int reached
          in
          let median_hitting =
            if Array.length reached = 0 then nan
            else reached |> Array.map float_of_int |> Stats.quantile 0.5
          in
          hitting_rows :=
            [
              float_cell alpha;
              float_cell threshold;
              float_cell reach_rate;
              float_cell mean_hitting;
              float_cell median_hitting;
            ]
            :: !hitting_rows)
        thresholds)
    [| 0.05; 0.20; 0.40 |];

  Csv_writer.write (output_path output_dir "price_discovery.csv")
    (List.rev !path_rows);
  Csv_writer.write (output_path output_dir "price_discovery_hitting.csv")
    (List.rev !hitting_rows)

let evaluate_information_strategy ~market ~tapes ~strategy_name ~make_strategy =
  let episode_count = Array.length tapes in
  let pnl_samples = Array.make episode_count 0.0 in
  let rmse_samples = Array.make episode_count 0.0 in
  let informed_pnl_samples = Array.make episode_count 0.0 in
  let noise_pnl_samples = Array.make episode_count 0.0 in
  let spread_samples = Array.make episode_count 0.0 in
  let alpha_estimates = Array.make episode_count 0.0 in

  Array.iteri
    (fun episode_no tape ->
      let episode =
        Information_sim.run ~market ~tape ~starting_strategy:(make_strategy ())
          ~keep_trace:false
      in
      pnl_samples.(episode_no) <- episode.terminal_wealth;
      rmse_samples.(episode_no) <- episode.fair_value_rmse;
      informed_pnl_samples.(episode_no) <- episode.informed_flow_pnl;
      noise_pnl_samples.(episode_no) <- episode.noise_flow_pnl;
      spread_samples.(episode_no) <- episode.mean_quoted_spread;
      alpha_estimates.(episode_no) <- episode.final_alpha_estimate)
    tapes;

  {
    strategy_name;
    pnl_samples;
    rmse_samples;
    informed_pnl_samples;
    noise_pnl_samples;
    spread_samples;
    alpha_estimates;
  }

let write_strategy_row true_alpha batch =
  let pnl = Stats.summarise batch.pnl_samples in
  [
    float_cell true_alpha;
    batch.strategy_name;
    float_cell pnl.mean;
    float_cell pnl.standard_deviation;
    float_cell pnl.p05;
    float_cell pnl.median;
    float_cell pnl.p95;
    float_cell pnl.standard_error;
    float_cell (Stats.mean batch.rmse_samples);
    float_cell (Stats.mean batch.informed_pnl_samples);
    float_cell (Stats.mean batch.noise_pnl_samples);
    float_cell (Stats.mean batch.spread_samples);
  ]

let paired_difference left right =
  if Array.length left <> Array.length right then
    invalid_arg "paired samples must have the same length";
  Array.init (Array.length left) (fun episode_no ->
      left.(episode_no) -. right.(episode_no))

let strategy_comparison ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let rng = Random_tools.seeded ~seed ~salt:303 in
  let strategy_rows =
    ref
      [
        [
          "true_alpha";
          "strategy";
          "mean_pnl";
          "sd_pnl";
          "p05_pnl";
          "median_pnl";
          "p95_pnl";
          "standard_error";
          "mean_fair_value_rmse";
          "mean_informed_flow_pnl";
          "mean_noise_flow_pnl";
          "mean_spread";
        ];
      ]
  in
  let paired_rows =
    ref
      [
        [
          "true_alpha";
          "mean_pnl_delta";
          "sd_pnl_delta";
          "p05_pnl_delta";
          "p95_pnl_delta";
          "pnl_delta_standard_error";
          "pnl_delta_ci_low";
          "pnl_delta_ci_high";
          "mean_rmse_delta";
          "rmse_delta_standard_error";
          "rmse_delta_ci_low";
          "rmse_delta_ci_high";
        ];
      ]
  in

  Array.iter
    (fun true_alpha ->
      let tapes =
        Array.init run_size.strategy_episodes (fun _episode_no ->
            Order_tape.generate ~rng ~alpha:true_alpha
              ~trade_count:run_size.information_trades ())
      in
      let static_run =
        evaluate_information_strategy ~market:baseline_market ~tapes
          ~strategy_name:"static" ~make_strategy:(fun () ->
            Strategy.static ~prior_high:baseline_market.prior_high
              ~assumed_alpha:true_alpha)
      in
      let bayesian_run =
        evaluate_information_strategy ~market:baseline_market ~tapes
          ~strategy_name:"bayesian" ~make_strategy:(fun () ->
            Strategy.bayesian ~prior_high:baseline_market.prior_high
              ~assumed_alpha:true_alpha)
      in
      strategy_rows :=
        write_strategy_row true_alpha bayesian_run
        :: write_strategy_row true_alpha static_run
        :: !strategy_rows;

      let pnl_delta =
        paired_difference bayesian_run.pnl_samples static_run.pnl_samples
      in
      let rmse_delta =
        paired_difference bayesian_run.rmse_samples static_run.rmse_samples
      in
      let pnl_stats = Stats.summarise pnl_delta in
      let rmse_stats = Stats.summarise rmse_delta in
      let pnl_margin = 1.96 *. pnl_stats.standard_error in
      let rmse_margin = 1.96 *. rmse_stats.standard_error in
      paired_rows :=
        [
          float_cell true_alpha;
          float_cell pnl_stats.mean;
          float_cell pnl_stats.standard_deviation;
          float_cell pnl_stats.p05;
          float_cell pnl_stats.p95;
          float_cell pnl_stats.standard_error;
          float_cell (pnl_stats.mean -. pnl_margin);
          float_cell (pnl_stats.mean +. pnl_margin);
          float_cell rmse_stats.mean;
          float_cell rmse_stats.standard_error;
          float_cell (rmse_stats.mean -. rmse_margin);
          float_cell (rmse_stats.mean +. rmse_margin);
        ]
        :: !paired_rows)
    [| 0.05; 0.10; 0.20; 0.30; 0.40 |];

  Csv_writer.write (output_path output_dir "strategy_comparison.csv")
    (List.rev !strategy_rows);
  Csv_writer.write (output_path output_dir "paired_strategy_comparison.csv")
    (List.rev !paired_rows)

let misspecification ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let rng = Random_tools.seeded ~seed ~salt:404 in
  let csv_rows =
    ref
      [
        [
          "true_alpha";
          "assumed_alpha";
          "mean_pnl";
          "sd_pnl";
          "p05_pnl";
          "mean_fair_value_rmse";
          "mean_informed_flow_pnl";
          "mean_noise_flow_pnl";
          "mean_spread";
        ];
      ]
  in

  Array.iter
    (fun true_alpha ->
      let tapes =
        Array.init run_size.misspec_episodes (fun _episode_no ->
            Order_tape.generate ~rng ~alpha:true_alpha
              ~trade_count:run_size.information_trades ())
      in
      Array.iter
        (fun assumed_alpha ->
          let batch =
            evaluate_information_strategy ~market:baseline_market ~tapes
              ~strategy_name:"bayesian" ~make_strategy:(fun () ->
                Strategy.bayesian ~prior_high:baseline_market.prior_high
                  ~assumed_alpha)
          in
          let pnl = Stats.summarise batch.pnl_samples in
          csv_rows :=
            [
              float_cell true_alpha;
              float_cell assumed_alpha;
              float_cell pnl.mean;
              float_cell pnl.standard_deviation;
              float_cell pnl.p05;
              float_cell (Stats.mean batch.rmse_samples);
              float_cell (Stats.mean batch.informed_pnl_samples);
              float_cell (Stats.mean batch.noise_pnl_samples);
              float_cell (Stats.mean batch.spread_samples);
            ]
            :: !csv_rows)
        study_alphas)
    study_alphas;

  Csv_writer.write (output_path output_dir "misspecification.csv")
    (List.rev !csv_rows)

let unknown_alpha ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let rng = Random_tools.seeded ~seed ~salt:505 in
  let candidate_grid = Array.copy study_alphas in
  let csv_rows =
    ref
      [
        [
          "true_alpha";
          "strategy";
          "mean_pnl";
          "sd_pnl";
          "p05_pnl";
          "mean_fair_value_rmse";
          "mean_alpha_estimate";
          "alpha_mae";
          "mean_spread";
        ];
      ]
  in

  Array.iter
    (fun true_alpha ->
      let tapes =
        Array.init run_size.unknown_alpha_episodes (fun _episode_no ->
            Order_tape.generate ~rng ~alpha:true_alpha
              ~trade_count:run_size.discovery_trades ())
      in
      let candidates =
        [
          ( "oracle",
            fun () ->
              Strategy.bayesian ~prior_high:baseline_market.prior_high
                ~assumed_alpha:true_alpha );
          ( "fixed-0.20",
            fun () ->
              Strategy.bayesian ~prior_high:baseline_market.prior_high
                ~assumed_alpha:0.20 );
          ( "joint-bayes",
            fun () ->
              Strategy.joint ~prior_high:baseline_market.prior_high
                ~alpha_grid:candidate_grid );
        ]
      in
      List.iter
        (fun (strategy_name, make_strategy) ->
          let batch =
            evaluate_information_strategy ~market:baseline_market ~tapes
              ~strategy_name ~make_strategy
          in
          let pnl = Stats.summarise batch.pnl_samples in
          let alpha_mae_samples =
            Array.map
              (fun alpha_estimate -> abs_float (alpha_estimate -. true_alpha))
              batch.alpha_estimates
          in
          csv_rows :=
            [
              float_cell true_alpha;
              strategy_name;
              float_cell pnl.mean;
              float_cell pnl.standard_deviation;
              float_cell pnl.p05;
              float_cell (Stats.mean batch.rmse_samples);
              float_cell (Stats.mean batch.alpha_estimates);
              float_cell (Stats.mean alpha_mae_samples);
              float_cell (Stats.mean batch.spread_samples);
            ]
            :: !csv_rows)
        candidates)
    study_alphas;

  Csv_writer.write (output_path output_dir "unknown_alpha.csv")
    (List.rev !csv_rows)

let first_stable_time estimates ~switch_after ~target =
  let tolerance = 0.10 in
  let stable_for = 5 in
  let last_slot = Array.length estimates - 1 in
  let rec window_is_stable start offset =
    if offset = stable_for then true
    else if abs_float (estimates.(start + offset) -. target) > tolerance then false
    else window_is_stable start (offset + 1)
  in
  let rec search time_slot =
    if time_slot + stable_for - 1 > last_slot then -1
    else if window_is_stable time_slot 0 then time_slot - switch_after
    else search (time_slot + 1)
  in
  search (switch_after + 1)

let regime_change ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let alpha_before = 0.05 in
  let alpha_after = 0.40 in
  let switch_after = run_size.regime_trades / 2 in
  let candidate_grid = Array.copy study_alphas in
  let tapes =
    Array.init run_size.regime_paths (fun path_no ->
        let rng = Random.State.make [| seed; 808; path_no |] in
        Order_tape.generate_regime ~rng ~alpha_before ~alpha_after ~switch_after
          ~trade_count:run_size.regime_trades ())
  in
  let curve_rows =
    ref
      [
        [
          "strategy";
          "window";
          "trade_no";
          "true_alpha";
          "q25_alpha_estimate";
          "median_alpha_estimate";
          "q75_alpha_estimate";
          "median_spread";
        ];
      ]
  in
  let adaptation_rows =
    ref
      [
        [
          "strategy";
          "window";
          "reach_rate";
          "mean_adaptation_delay";
          "median_adaptation_delay";
          "mean_post_switch_alpha_mae";
        ];
      ]
  in
  let candidates =
    [
      ( "full-history",
        0,
        fun () ->
          Strategy.joint ~prior_high:baseline_market.prior_high
            ~alpha_grid:candidate_grid );
      ( "rolling-20",
        20,
        fun () ->
          Strategy.rolling_joint ~prior_high:baseline_market.prior_high
            ~alpha_grid:candidate_grid ~window:20 );
      ( "rolling-50",
        50,
        fun () ->
          Strategy.rolling_joint ~prior_high:baseline_market.prior_high
            ~alpha_grid:candidate_grid ~window:50 );
      ( "rolling-100",
        100,
        fun () ->
          Strategy.rolling_joint ~prior_high:baseline_market.prior_high
            ~alpha_grid:candidate_grid ~window:100 );
    ]
  in

  List.iter
    (fun (strategy_name, window, make_strategy) ->
      let alpha_by_trade =
        Array.init (run_size.regime_trades + 1) (fun _trade_no ->
            Array.make run_size.regime_paths 0.0)
      in
      let spread_by_trade =
        Array.init (run_size.regime_trades + 1) (fun _trade_no ->
            Array.make run_size.regime_paths 0.0)
      in
      let adaptation_delays = Array.make run_size.regime_paths (-1) in
      let post_switch_mae = Array.make run_size.regime_paths 0.0 in

      Array.iteri
        (fun path_no tape ->
          let active_strategy = ref (make_strategy ()) in
          let snapshot trade_no =
            alpha_by_trade.(trade_no).(path_no) <-
              Strategy.alpha_estimate !active_strategy;
            let live_quote = Strategy.quote baseline_market !active_strategy in
            spread_by_trade.(trade_no).(path_no) <- live_quote.ask -. live_quote.bid
          in
          snapshot 0;
          Array.iteri
            (fun trade_slot arrival ->
              active_strategy := Strategy.observe !active_strategy arrival.side;
              snapshot (trade_slot + 1))
            tape.arrivals;
          let path_estimates =
            Array.init (run_size.regime_trades + 1) (fun trade_no ->
                alpha_by_trade.(trade_no).(path_no))
          in
          adaptation_delays.(path_no) <-
            first_stable_time path_estimates ~switch_after ~target:alpha_after;
          let running_error = ref 0.0 in
          let post_count = run_size.regime_trades - switch_after in
          for trade_no = switch_after + 1 to run_size.regime_trades do
            running_error :=
              !running_error
              +. abs_float (path_estimates.(trade_no) -. alpha_after)
          done;
          post_switch_mae.(path_no) <- !running_error /. float_of_int post_count)
        tapes;

      Array.iteri
        (fun trade_no alpha_slice ->
          let true_alpha =
            if trade_no < switch_after then alpha_before else alpha_after
          in
          curve_rows :=
            [
              strategy_name;
              int_cell window;
              int_cell trade_no;
              float_cell true_alpha;
              float_cell (Stats.quantile 0.25 alpha_slice);
              float_cell (Stats.quantile 0.50 alpha_slice);
              float_cell (Stats.quantile 0.75 alpha_slice);
              float_cell (Stats.quantile 0.50 spread_by_trade.(trade_no));
            ]
            :: !curve_rows)
        alpha_by_trade;

      let reached =
        adaptation_delays
        |> Array.to_list
        |> List.filter (fun delay -> delay >= 0)
        |> Array.of_list
      in
      let reach_rate =
        float_of_int (Array.length reached) /. float_of_int run_size.regime_paths
      in
      let mean_delay =
        if Array.length reached = 0 then nan else Stats.mean_int reached
      in
      let median_delay =
        if Array.length reached = 0 then nan
        else reached |> Array.map float_of_int |> Stats.quantile 0.5
      in
      adaptation_rows :=
        [
          strategy_name;
          int_cell window;
          float_cell reach_rate;
          float_cell mean_delay;
          float_cell median_delay;
          float_cell (Stats.mean post_switch_mae);
        ]
        :: !adaptation_rows)
    candidates;

  Csv_writer.write (output_path output_dir "regime_change.csv")
    (List.rev !curve_rows);
  Csv_writer.write (output_path output_dir "regime_adaptation.csv")
    (List.rev !adaptation_rows)

let inventory_tradeoff ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let csv_rows =
    ref
      [
        [
          "inventory_skew";
          "mean_pnl";
          "sd_pnl";
          "p05_pnl";
          "median_pnl";
          "p95_pnl";
          "mean_max_abs_inventory";
          "mean_abs_inventory";
          "mean_fill_count";
        ];
      ]
  in
  let skew_grid = [| 0.0; 0.02; 0.05; 0.10; 0.20; 0.35 |] in

  Array.iter
    (fun inventory_skew ->
      let pnl_samples = Array.make run_size.inventory_episodes 0.0 in
      let max_inventory_samples = Array.make run_size.inventory_episodes 0.0 in
      let mean_inventory_samples = Array.make run_size.inventory_episodes 0.0 in
      let fill_samples = Array.make run_size.inventory_episodes 0.0 in
      for episode_no = 0 to run_size.inventory_episodes - 1 do
        let rng = Random.State.make [| seed; 606; episode_no |] in
        let episode =
          Inventory_sim.run_episode ~rng
            {
              start_mid = 100.0;
              step_count = run_size.inventory_steps;
              volatility = 0.45;
              half_spread = 0.75;
              base_fill = 0.80;
              fill_decay = 1.10;
              inventory_skew;
            }
        in
        pnl_samples.(episode_no) <- episode.terminal_wealth;
        max_inventory_samples.(episode_no) <-
          float_of_int episode.max_abs_inventory;
        mean_inventory_samples.(episode_no) <- episode.mean_abs_inventory;
        fill_samples.(episode_no) <- float_of_int episode.fill_count
      done;
      let pnl = Stats.summarise pnl_samples in
      csv_rows :=
        [
          float_cell inventory_skew;
          float_cell pnl.mean;
          float_cell pnl.standard_deviation;
          float_cell pnl.p05;
          float_cell pnl.median;
          float_cell pnl.p95;
          float_cell (Stats.mean max_inventory_samples);
          float_cell (Stats.mean mean_inventory_samples);
          float_cell (Stats.mean fill_samples);
        ]
        :: !csv_rows)
    skew_grid;

  Csv_writer.write (output_path output_dir "inventory_tradeoff.csv")
    (List.rev !csv_rows)

let quote_distance ~seed ~output_dir ~quick =
  let run_size = workload ~quick in
  let csv_rows =
    ref
      [
        [
          "half_spread";
          "mean_pnl";
          "sd_pnl";
          "p05_pnl";
          "mean_fill_count";
          "mean_max_abs_inventory";
        ];
      ]
  in
  let spread_grid = [| 0.10; 0.25; 0.50; 0.75; 1.00; 1.50; 2.00; 3.00 |] in

  Array.iter
    (fun half_spread ->
      let pnl_samples = Array.make run_size.inventory_episodes 0.0 in
      let fill_samples = Array.make run_size.inventory_episodes 0.0 in
      let max_inventory_samples = Array.make run_size.inventory_episodes 0.0 in
      for episode_no = 0 to run_size.inventory_episodes - 1 do
        let rng = Random.State.make [| seed; 707; episode_no |] in
        let episode =
          Inventory_sim.run_episode ~rng
            {
              start_mid = 100.0;
              step_count = run_size.inventory_steps;
              volatility = 0.45;
              half_spread;
              base_fill = 0.80;
              fill_decay = 1.10;
              inventory_skew = 0.08;
            }
        in
        pnl_samples.(episode_no) <- episode.terminal_wealth;
        fill_samples.(episode_no) <- float_of_int episode.fill_count;
        max_inventory_samples.(episode_no) <-
          float_of_int episode.max_abs_inventory
      done;
      let pnl = Stats.summarise pnl_samples in
      csv_rows :=
        [
          float_cell half_spread;
          float_cell pnl.mean;
          float_cell pnl.standard_deviation;
          float_cell pnl.p05;
          float_cell (Stats.mean fill_samples);
          float_cell (Stats.mean max_inventory_samples);
        ]
        :: !csv_rows)
    spread_grid;

  Csv_writer.write (output_path output_dir "quote_distance.csv")
    (List.rev !csv_rows)

let write_manifest ~seed ~output_dir ~quick =
  let scale = if quick then "quick" else "full" in
  Csv_writer.write (output_path output_dir "run_manifest.csv")
    [
      [ "field"; "value" ];
      [ "seed"; string_of_int seed ];
      [ "profile"; scale ];
      [ "engine"; "ocaml" ];
      [ "experiment_count"; "8" ];
    ]

let run_all ~seed ~output_dir ~quick =
  Csv_writer.ensure_directory output_dir;
  spread_validation ~seed ~output_dir ~quick;
  price_discovery ~seed ~output_dir ~quick;
  strategy_comparison ~seed ~output_dir ~quick;
  misspecification ~seed ~output_dir ~quick;
  unknown_alpha ~seed ~output_dir ~quick;
  regime_change ~seed ~output_dir ~quick;
  inventory_tradeoff ~seed ~output_dir ~quick;
  quote_distance ~seed ~output_dir ~quick;
  write_manifest ~seed ~output_dir ~quick

let run_named ~name ~seed ~output_dir ~quick =
  Csv_writer.ensure_directory output_dir;
  match name with
  | "all" -> run_all ~seed ~output_dir ~quick
  | "spread" | "spread-validation" -> spread_validation ~seed ~output_dir ~quick
  | "price" | "price-discovery" -> price_discovery ~seed ~output_dir ~quick
  | "strategy" | "strategy-comparison" ->
      strategy_comparison ~seed ~output_dir ~quick
  | "misspecification" -> misspecification ~seed ~output_dir ~quick
  | "unknown-alpha" -> unknown_alpha ~seed ~output_dir ~quick
  | "regime" | "regime-change" -> regime_change ~seed ~output_dir ~quick
  | "inventory" -> inventory_tradeoff ~seed ~output_dir ~quick
  | "quote-distance" -> quote_distance ~seed ~output_dir ~quick
  | unfamiliar ->
      invalid_arg (Printf.sprintf "unknown experiment: %s" unfamiliar)
