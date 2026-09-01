open Market_maker

let () =
  let experiment_name = ref "all" in
  let seed = ref 20260831 in
  let output_dir = ref "results/data" in
  let quick = ref false in
  let usage =
    "market-maker [experiment] [--seed N] [--out DIR] [--quick]\n\n\
     Experiments: all, spread-validation, price-discovery, strategy-comparison,\n\
     misspecification, unknown-alpha, regime-change, inventory, quote-distance"
  in
  let options =
    [
      ("--seed", Arg.Set_int seed, "Random seed (default: 20260831)");
      ("--out", Arg.Set_string output_dir, "Directory for CSV output");
      ("--quick", Arg.Set quick, "Use the reduced CI-sized workload");
    ]
  in
  Arg.parse options (fun chosen -> experiment_name := chosen) usage;
  Printf.printf "Running %s (%s profile, seed %d)\n%!" !experiment_name
    (if !quick then "quick" else "full") !seed;
  (try
     Experiments.run_named ~name:!experiment_name ~seed:!seed
       ~output_dir:!output_dir ~quick:!quick
   with Invalid_argument message ->
     Printf.eprintf "error: %s\n%!" message;
     exit 2);
  Printf.printf "Wrote CSV files to %s\n%!" !output_dir
