# Generated Results

The checked-in reference files use seed `20260831`, the full workload, and the engine recorded in `data/run_manifest.csv`. See [`docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) for the reproduction and attribution rules.

## Data files

### `spread_validation.csv`

One row per informed-trader probability:

```text
alpha
theoretical_bid
theoretical_ask
theoretical_spread
simulated_bid
simulated_ask
simulated_spread
buy_count
sell_count
```

### `price_discovery.csv`

Posterior confidence in the true state, summarised across paths at every trade count:

```text
alpha
trade_no
q25_correct_confidence
median_correct_confidence
q75_correct_confidence
```

### `price_discovery_hitting.csv`

Threshold-crossing statistics:

```text
alpha
threshold
reach_rate
mean_hitting_time
median_hitting_time
```

Mean and median hitting times are conditional on reaching the threshold inside the experiment horizon, so they must be read alongside `reach_rate`.

### `strategy_comparison.csv`

Static and Bayesian strategy summaries under correct specification:

```text
true_alpha
strategy
mean_pnl
sd_pnl
p05_pnl
median_pnl
p95_pnl
standard_error
mean_fair_value_rmse
mean_informed_flow_pnl
mean_noise_flow_pnl
mean_spread
```

### `paired_strategy_comparison.csv`

Bayesian-minus-static differences calculated episode by episode on shared order tapes:

```text
true_alpha
mean_pnl_delta
sd_pnl_delta
p05_pnl_delta
p95_pnl_delta
pnl_delta_standard_error
pnl_delta_ci_low
pnl_delta_ci_high
mean_rmse_delta
rmse_delta_standard_error
rmse_delta_ci_low
rmse_delta_ci_high
```

### `misspecification.csv`

Bayesian strategy metrics for every tested pair of true and assumed information intensity:

```text
true_alpha
assumed_alpha
mean_pnl
sd_pnl
p05_pnl
mean_fair_value_rmse
mean_informed_flow_pnl
mean_noise_flow_pnl
mean_spread
```

### `unknown_alpha.csv`

Comparison of the oracle, fixed-parameter, and joint Bayesian strategies:

```text
true_alpha
strategy
mean_pnl
sd_pnl
p05_pnl
mean_fair_value_rmse
mean_alpha_estimate
alpha_mae
mean_spread
```

### `regime_change.csv`

Time-series summaries for full-history and rolling joint filters:

```text
strategy
window
trade_no
true_alpha
q25_alpha_estimate
median_alpha_estimate
q75_alpha_estimate
median_spread
```

### `regime_adaptation.csv`

Path-level adaptation performance after the information regime changes:

```text
strategy
window
reach_rate
mean_adaptation_delay
median_adaptation_delay
mean_post_switch_alpha_mae
```

An estimator is counted as adapted once its alpha estimate stays within `0.10` of the new true value for five consecutive observations.

### `inventory_tradeoff.csv`

Inventory and P&L metrics as the skew coefficient changes:

```text
inventory_skew
mean_pnl
sd_pnl
p05_pnl
median_pnl
p95_pnl
mean_max_abs_inventory
mean_abs_inventory
mean_fill_count
```

### `quote_distance.csv`

Execution and P&L metrics as the half-spread changes:

```text
half_spread
mean_pnl
sd_pnl
p05_pnl
mean_fill_count
mean_max_abs_inventory
```

### `run_manifest.csv`

Records the seed, workload profile, generating engine, and experiment count attached to the directory.

## Figures

The `figures/` directory contains fifteen numbered figures, each in PDF and PNG. The paper imports the PDF versions; the repository front page uses PNG.

```text
01  theoretical and simulated informational spread
02  posterior price discovery
03  strategy fair-value RMSE
04  terminal P&L dispersion
05  paired RMSE difference
06  misspecification RMSE heatmap
07  misspecification P&L heatmap
08  unknown-alpha strategy RMSE
09  alpha calibration
10  regime-change alpha estimates
11  post-switch alpha error
12  inventory exposure
13  inventory P&L
14  quote-distance P&L
15  quote-distance fill count
```
