#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


REQUIRED_FILES = {
    "spread_validation.csv",
    "price_discovery.csv",
    "price_discovery_hitting.csv",
    "strategy_comparison.csv",
    "paired_strategy_comparison.csv",
    "misspecification.csv",
    "unknown_alpha.csv",
    "regime_change.csv",
    "regime_adaptation.csv",
    "inventory_tradeoff.csv",
    "quote_distance.csv",
    "run_manifest.csv",
}


def demand(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def check_numeric_frame(frame: pd.DataFrame, name: str, *, allow_nan: set[str] | None = None) -> None:
    allowed = allow_nan or set()
    for column_name in frame.select_dtypes(include=[np.number]).columns:
        numeric_values = frame[column_name].to_numpy(dtype=float)
        if column_name in allowed:
            demand(not np.any(np.isinf(numeric_values)), f"{name}: {column_name} contains infinity")
        else:
            demand(np.all(np.isfinite(numeric_values)), f"{name}: {column_name} contains non-finite values")


def main() -> None:
    parser = argparse.ArgumentParser(description="Check experiment outputs for broken accounting or implausible regressions")
    parser.add_argument("--input", type=Path, default=Path("results/data"))
    args = parser.parse_args()

    missing = sorted(REQUIRED_FILES - {path.name for path in args.input.glob("*.csv")})
    demand(not missing, f"missing output files: {', '.join(missing)}")

    manifest = pd.read_csv(args.input / "run_manifest.csv").set_index("field")["value"]
    profile = str(manifest.get("profile", "unknown"))
    demand(str(manifest.get("experiment_count", "")) == "8", "manifest experiment count is stale")

    spread = pd.read_csv(args.input / "spread_validation.csv")
    check_numeric_frame(spread, "spread_validation")
    demand(np.allclose(spread["theoretical_spread"], 20.0 * spread["alpha"]), "closed-form spread changed")
    spread_tolerance = 1.0 if profile == "quick" else 0.30
    max_gap = float(np.max(np.abs(spread["simulated_spread"] - spread["theoretical_spread"])))
    demand(max_gap < spread_tolerance, f"spread simulation misses theory by {max_gap:.3f}")
    demand(np.all(spread[["buy_count", "sell_count"]].to_numpy() > 0), "empty conditioning bucket in spread run")

    discovery = pd.read_csv(args.input / "price_discovery.csv")
    check_numeric_frame(discovery, "price_discovery")
    demand(discovery["median_correct_confidence"].between(0.0, 1.0).all(), "posterior confidence left [0,1]")

    hitting = pd.read_csv(args.input / "price_discovery_hitting.csv")
    check_numeric_frame(
        hitting,
        "price_discovery_hitting",
        allow_nan={"mean_hitting_time", "median_hitting_time"},
    )
    demand(hitting["reach_rate"].between(0.0, 1.0).all(), "hitting rate left [0,1]")

    comparison = pd.read_csv(args.input / "strategy_comparison.csv")
    check_numeric_frame(comparison, "strategy_comparison")
    for true_alpha, alpha_slice in comparison.groupby("true_alpha"):
        indexed = alpha_slice.set_index("strategy")
        demand({"static", "bayesian"}.issubset(indexed.index), f"missing strategy at alpha={true_alpha}")
        demand(
            indexed.loc["bayesian", "mean_fair_value_rmse"]
            < indexed.loc["static", "mean_fair_value_rmse"],
            f"Bayesian RMSE did not improve at alpha={true_alpha}",
        )
        accounting_gap = np.abs(
            alpha_slice["mean_pnl"]
            - alpha_slice["mean_informed_flow_pnl"]
            - alpha_slice["mean_noise_flow_pnl"]
        )
        demand(np.max(accounting_gap) < 1e-8, f"P&L attribution does not reconcile at alpha={true_alpha}")

    paired = pd.read_csv(args.input / "paired_strategy_comparison.csv")
    check_numeric_frame(paired, "paired_strategy_comparison")
    demand((paired["mean_rmse_delta"] < 0.0).all(), "paired RMSE differences should favour Bayesian updating")
    if profile != "quick":
        demand((paired["rmse_delta_ci_high"] < 0.0).all(), "full-run RMSE confidence interval crosses zero")

    misspec = pd.read_csv(args.input / "misspecification.csv")
    check_numeric_frame(misspec, "misspecification")
    demand(not misspec.duplicated(["true_alpha", "assumed_alpha"]).any(), "duplicate misspecification cells")
    misspec_gap = np.abs(
        misspec["mean_pnl"]
        - misspec["mean_informed_flow_pnl"]
        - misspec["mean_noise_flow_pnl"]
    )
    demand(np.max(misspec_gap) < 1e-8, "misspecification P&L attribution does not reconcile")

    unknown = pd.read_csv(args.input / "unknown_alpha.csv")
    check_numeric_frame(unknown, "unknown_alpha")
    demand(((unknown["mean_alpha_estimate"] >= 0.05 - 1e-12) & (unknown["mean_alpha_estimate"] <= 0.50 + 1e-12)).all(), "alpha estimate left the candidate grid")

    regime_curve = pd.read_csv(args.input / "regime_change.csv")
    check_numeric_frame(regime_curve, "regime_change")
    demand(((regime_curve["median_alpha_estimate"] >= 0.05 - 1e-12) & (regime_curve["median_alpha_estimate"] <= 0.50 + 1e-12)).all(), "regime estimate left the candidate grid")

    adaptation = pd.read_csv(args.input / "regime_adaptation.csv")
    check_numeric_frame(
        adaptation,
        "regime_adaptation",
        allow_nan={"mean_adaptation_delay", "median_adaptation_delay"},
    )
    adaptation_index = adaptation.set_index("strategy")
    demand(
        adaptation_index.loc["rolling-20", "mean_post_switch_alpha_mae"]
        < adaptation_index.loc["full-history", "mean_post_switch_alpha_mae"],
        "rolling regime estimator failed to improve post-switch error",
    )

    inventory = pd.read_csv(args.input / "inventory_tradeoff.csv")
    check_numeric_frame(inventory, "inventory_tradeoff")
    inventory_index = inventory.set_index("inventory_skew")
    demand(
        inventory_index.loc[0.10, "mean_max_abs_inventory"]
        < inventory_index.loc[0.0, "mean_max_abs_inventory"],
        "inventory skew did not reduce position exposure",
    )

    quote_distance = pd.read_csv(args.input / "quote_distance.csv")
    check_numeric_frame(quote_distance, "quote_distance")
    sorted_quotes = quote_distance.sort_values("half_spread")
    demand(np.all(np.diff(sorted_quotes["mean_fill_count"]) < 0.0), "fill count is not decreasing with quote distance")
    best_slot = int(np.argmax(sorted_quotes["mean_pnl"].to_numpy()))
    demand(0 < best_slot < len(sorted_quotes) - 1, "quote-distance optimum fell on a grid boundary")

    print(
        f"output checks passed ({profile} profile, engine={manifest.get('engine', 'unknown')}, "
        f"max spread error={max_gap:.3f})"
    )


if __name__ == "__main__":
    main()
