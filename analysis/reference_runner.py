#!/usr/bin/env python3
"""Independent numerical implementation of the model used for parity checks."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


LOW_VALUE = 90.0
HIGH_VALUE = 110.0
PRIOR_HIGH = 0.5


@dataclass(frozen=True)
class Workload:
    spread_trials: int
    discovery_paths: int
    strategy_episodes: int
    misspec_episodes: int
    unknown_alpha_episodes: int
    inventory_episodes: int
    regime_paths: int
    information_trades: int
    discovery_trades: int
    inventory_steps: int
    regime_trades: int


def choose_workload(quick: bool) -> Workload:
    if quick:
        return Workload(5_000, 250, 350, 120, 180, 250, 80, 30, 45, 90, 120)
    return Workload(100_000, 3_000, 6_000, 1_800, 2_500, 3_500, 800, 60, 80, 300, 200)


def update_high_probability(
    prior_high: np.ndarray,
    alpha: float,
    customer_buys: np.ndarray,
) -> np.ndarray:
    high_likelihood = np.where(customer_buys, (1.0 + alpha) / 2.0, (1.0 - alpha) / 2.0)
    low_likelihood = np.where(customer_buys, (1.0 - alpha) / 2.0, (1.0 + alpha) / 2.0)
    high_mass = prior_high * high_likelihood
    return high_mass / (high_mass + (1.0 - prior_high) * low_likelihood)


def quote_from_belief(prior_high: np.ndarray, alpha: float) -> tuple[np.ndarray, np.ndarray]:
    buy_marker = np.ones(prior_high.shape, dtype=bool)
    sell_marker = np.zeros(prior_high.shape, dtype=bool)
    ask_high = update_high_probability(prior_high, alpha, buy_marker)
    bid_high = update_high_probability(prior_high, alpha, sell_marker)
    ask = LOW_VALUE + (HIGH_VALUE - LOW_VALUE) * ask_high
    bid = LOW_VALUE + (HIGH_VALUE - LOW_VALUE) * bid_high
    return bid, ask


def make_order_tape(
    rng: np.random.Generator,
    *,
    true_alpha: float,
    episodes: int,
    trades: int,
    hidden_high: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    hidden_states = rng.random(episodes) < 0.5 if hidden_high is None else hidden_high
    informed_mask = rng.random((episodes, trades)) < true_alpha
    noise_buys = rng.random((episodes, trades)) < 0.5
    customer_buys = np.where(informed_mask, hidden_states[:, None], noise_buys)
    return hidden_states, informed_mask, customer_buys


def make_regime_tape(
    rng: np.random.Generator,
    *,
    episodes: int,
    trades: int,
    switch_after: int,
    alpha_before: float,
    alpha_after: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    hidden_states = rng.random(episodes) < 0.5
    alpha_schedule = np.where(
        np.arange(trades) < switch_after,
        alpha_before,
        alpha_after,
    )
    informed_mask = rng.random((episodes, trades)) < alpha_schedule[None, :]
    noise_buys = rng.random((episodes, trades)) < 0.5
    customer_buys = np.where(informed_mask, hidden_states[:, None], noise_buys)
    return hidden_states, informed_mask, customer_buys


def summarise(sample: np.ndarray) -> dict[str, float]:
    return {
        "mean": float(np.mean(sample)),
        "sd": float(np.std(sample, ddof=1)),
        "p05": float(np.quantile(sample, 0.05)),
        "median": float(np.quantile(sample, 0.50)),
        "p95": float(np.quantile(sample, 0.95)),
        "se": float(np.std(sample, ddof=1) / np.sqrt(sample.size)),
    }


def simulate_information_batch(
    *,
    hidden_high: np.ndarray,
    informed_mask: np.ndarray,
    customer_buys: np.ndarray,
    assumed_alpha: float,
    mode: str,
    alpha_grid: np.ndarray | None = None,
) -> dict[str, np.ndarray]:
    episode_count, trade_count = customer_buys.shape
    terminal_value = np.where(hidden_high, HIGH_VALUE, LOW_VALUE)
    cash_balance = np.zeros(episode_count)
    inventory_units = np.zeros(episode_count, dtype=np.int64)
    squared_error_pile = np.zeros(episode_count)
    informed_flow_pnl = np.zeros(episode_count)
    noise_flow_pnl = np.zeros(episode_count)
    spread_total = np.zeros(episode_count)

    if mode == "joint":
        if alpha_grid is None:
            raise ValueError("joint mode needs an alpha grid")
        alpha_slots = alpha_grid.size
        low_mass = np.full((episode_count, alpha_slots), (1.0 - PRIOR_HIGH) / alpha_slots)
        high_mass = np.full((episode_count, alpha_slots), PRIOR_HIGH / alpha_slots)
    else:
        posterior_high = np.full(episode_count, PRIOR_HIGH)

    for trade_slot in range(trade_count):
        buys_now = customer_buys[:, trade_slot]

        if mode == "joint":
            alpha_row = alpha_grid[None, :]
            buy_like_high = (1.0 + alpha_row) / 2.0
            buy_like_low = (1.0 - alpha_row) / 2.0
            sell_like_high = 1.0 - buy_like_high
            sell_like_low = 1.0 - buy_like_low

            ask_high_mass = high_mass * buy_like_high
            ask_low_mass = low_mass * buy_like_low
            ask_evidence = np.sum(ask_high_mass + ask_low_mass, axis=1)
            ask = (
                HIGH_VALUE * np.sum(ask_high_mass, axis=1)
                + LOW_VALUE * np.sum(ask_low_mass, axis=1)
            ) / ask_evidence

            bid_high_mass = high_mass * sell_like_high
            bid_low_mass = low_mass * sell_like_low
            bid_evidence = np.sum(bid_high_mass + bid_low_mass, axis=1)
            bid = (
                HIGH_VALUE * np.sum(bid_high_mass, axis=1)
                + LOW_VALUE * np.sum(bid_low_mass, axis=1)
            ) / bid_evidence
            belief_high = np.sum(high_mass, axis=1)
        else:
            bid, ask = quote_from_belief(posterior_high, assumed_alpha)
            belief_high = posterior_high

        fair_before = LOW_VALUE + (HIGH_VALUE - LOW_VALUE) * belief_high
        squared_error_pile += (fair_before - terminal_value) ** 2
        spread_total += ask - bid

        trade_price = np.where(buys_now, ask, bid)
        trade_pnl = np.where(buys_now, trade_price - terminal_value, terminal_value - trade_price)
        informed_flow_pnl += np.where(informed_mask[:, trade_slot], trade_pnl, 0.0)
        noise_flow_pnl += np.where(informed_mask[:, trade_slot], 0.0, trade_pnl)

        cash_balance += np.where(buys_now, ask, -bid)
        inventory_units += np.where(buys_now, -1, 1)

        if mode == "bayesian":
            posterior_high = update_high_probability(posterior_high, assumed_alpha, buys_now)
        elif mode == "joint":
            high_likelihood = np.where(buys_now[:, None], buy_like_high, sell_like_high)
            low_likelihood = np.where(buys_now[:, None], buy_like_low, sell_like_low)
            high_mass *= high_likelihood
            low_mass *= low_likelihood
            evidence = np.sum(high_mass + low_mass, axis=1, keepdims=True)
            high_mass /= evidence
            low_mass /= evidence
        # Static quotes are intentionally stale.

    if mode == "joint":
        final_alpha_estimate = np.sum((high_mass + low_mass) * alpha_grid[None, :], axis=1)
    else:
        final_alpha_estimate = np.full(episode_count, assumed_alpha)

    terminal_wealth = cash_balance + inventory_units * terminal_value
    return {
        "terminal_wealth": terminal_wealth,
        "rmse": np.sqrt(squared_error_pile / trade_count),
        "informed_pnl": informed_flow_pnl,
        "noise_pnl": noise_flow_pnl,
        "mean_spread": spread_total / trade_count,
        "alpha_estimate": final_alpha_estimate,
    }


def run_spread_validation(output_dir: Path, scale: Workload, seed: int) -> None:
    rng = np.random.default_rng(seed + 101)
    csv_rows: list[dict[str, float | int]] = []
    for alpha in np.arange(0.0, 0.5001, 0.05):
        hidden_high, _, customer_buys = make_order_tape(
            rng,
            true_alpha=float(alpha),
            episodes=scale.spread_trials,
            trades=1,
        )
        terminal_values = np.where(hidden_high, HIGH_VALUE, LOW_VALUE)
        buy_mask = customer_buys[:, 0]
        simulated_ask = float(np.mean(terminal_values[buy_mask]))
        simulated_bid = float(np.mean(terminal_values[~buy_mask]))
        theoretical_bid, theoretical_ask = quote_from_belief(
            np.array([PRIOR_HIGH]), float(alpha)
        )
        csv_rows.append(
            {
                "alpha": alpha,
                "theoretical_bid": theoretical_bid[0],
                "theoretical_ask": theoretical_ask[0],
                "theoretical_spread": theoretical_ask[0] - theoretical_bid[0],
                "simulated_bid": simulated_bid,
                "simulated_ask": simulated_ask,
                "simulated_spread": simulated_ask - simulated_bid,
                "buy_count": int(np.sum(buy_mask)),
                "sell_count": int(np.sum(~buy_mask)),
            }
        )
    pd.DataFrame(csv_rows).to_csv(output_dir / "spread_validation.csv", index=False)


def run_price_discovery(output_dir: Path, scale: Workload, seed: int) -> None:
    rng = np.random.default_rng(seed + 202)
    path_rows: list[dict[str, float | int]] = []
    hitting_rows: list[dict[str, float]] = []
    thresholds = (0.90, 0.95, 0.99)

    for alpha in (0.05, 0.20, 0.40):
        hidden_high, _, customer_buys = make_order_tape(
            rng,
            true_alpha=alpha,
            episodes=scale.discovery_paths,
            trades=scale.discovery_trades,
        )
        posterior_high = np.full(scale.discovery_paths, PRIOR_HIGH)
        confidence_paths = np.empty((scale.discovery_trades + 1, scale.discovery_paths))
        confidence_paths[0] = np.where(hidden_high, posterior_high, 1.0 - posterior_high)
        threshold_hits = np.full((len(thresholds), scale.discovery_paths), -1, dtype=np.int64)

        for trade_slot in range(scale.discovery_trades):
            posterior_high = update_high_probability(
                posterior_high,
                alpha,
                customer_buys[:, trade_slot],
            )
            confidence_now = np.where(hidden_high, posterior_high, 1.0 - posterior_high)
            confidence_paths[trade_slot + 1] = confidence_now
            for threshold_slot, threshold in enumerate(thresholds):
                newly_reached = (threshold_hits[threshold_slot] < 0) & (confidence_now >= threshold)
                threshold_hits[threshold_slot, newly_reached] = trade_slot + 1

        for trade_no, confidence_slice in enumerate(confidence_paths):
            path_rows.append(
                {
                    "alpha": alpha,
                    "trade_no": trade_no,
                    "q25_correct_confidence": np.quantile(confidence_slice, 0.25),
                    "median_correct_confidence": np.quantile(confidence_slice, 0.50),
                    "q75_correct_confidence": np.quantile(confidence_slice, 0.75),
                }
            )

        for threshold_slot, threshold in enumerate(thresholds):
            reached = threshold_hits[threshold_slot][threshold_hits[threshold_slot] >= 0]
            hitting_rows.append(
                {
                    "alpha": alpha,
                    "threshold": threshold,
                    "reach_rate": reached.size / scale.discovery_paths,
                    "mean_hitting_time": float(np.mean(reached)) if reached.size else np.nan,
                    "median_hitting_time": float(np.median(reached)) if reached.size else np.nan,
                }
            )

    pd.DataFrame(path_rows).to_csv(output_dir / "price_discovery.csv", index=False)
    pd.DataFrame(hitting_rows).to_csv(output_dir / "price_discovery_hitting.csv", index=False)


def batch_row(true_alpha: float, strategy_name: str, metrics: dict[str, np.ndarray]) -> dict[str, float | str]:
    pnl_stats = summarise(metrics["terminal_wealth"])
    return {
        "true_alpha": true_alpha,
        "strategy": strategy_name,
        "mean_pnl": pnl_stats["mean"],
        "sd_pnl": pnl_stats["sd"],
        "p05_pnl": pnl_stats["p05"],
        "median_pnl": pnl_stats["median"],
        "p95_pnl": pnl_stats["p95"],
        "standard_error": pnl_stats["se"],
        "mean_fair_value_rmse": float(np.mean(metrics["rmse"])),
        "mean_informed_flow_pnl": float(np.mean(metrics["informed_pnl"])),
        "mean_noise_flow_pnl": float(np.mean(metrics["noise_pnl"])),
        "mean_spread": float(np.mean(metrics["mean_spread"])),
    }


def run_strategy_comparison(output_dir: Path, scale: Workload, seed: int) -> None:
    rng = np.random.default_rng(seed + 303)
    strategy_rows: list[dict[str, float | str]] = []
    paired_rows: list[dict[str, float]] = []

    for true_alpha in (0.05, 0.10, 0.20, 0.30, 0.40):
        hidden_high, informed_mask, customer_buys = make_order_tape(
            rng,
            true_alpha=true_alpha,
            episodes=scale.strategy_episodes,
            trades=scale.information_trades,
        )
        static_metrics = simulate_information_batch(
            hidden_high=hidden_high,
            informed_mask=informed_mask,
            customer_buys=customer_buys,
            assumed_alpha=true_alpha,
            mode="static",
        )
        bayesian_metrics = simulate_information_batch(
            hidden_high=hidden_high,
            informed_mask=informed_mask,
            customer_buys=customer_buys,
            assumed_alpha=true_alpha,
            mode="bayesian",
        )
        strategy_rows.append(batch_row(true_alpha, "static", static_metrics))
        strategy_rows.append(batch_row(true_alpha, "bayesian", bayesian_metrics))

        pnl_delta = bayesian_metrics["terminal_wealth"] - static_metrics["terminal_wealth"]
        rmse_delta = bayesian_metrics["rmse"] - static_metrics["rmse"]
        pnl_stats = summarise(pnl_delta)
        rmse_stats = summarise(rmse_delta)
        paired_rows.append(
            {
                "true_alpha": true_alpha,
                "mean_pnl_delta": pnl_stats["mean"],
                "sd_pnl_delta": pnl_stats["sd"],
                "p05_pnl_delta": pnl_stats["p05"],
                "p95_pnl_delta": pnl_stats["p95"],
                "pnl_delta_standard_error": pnl_stats["se"],
                "pnl_delta_ci_low": pnl_stats["mean"] - 1.96 * pnl_stats["se"],
                "pnl_delta_ci_high": pnl_stats["mean"] + 1.96 * pnl_stats["se"],
                "mean_rmse_delta": rmse_stats["mean"],
                "rmse_delta_standard_error": rmse_stats["se"],
                "rmse_delta_ci_low": rmse_stats["mean"] - 1.96 * rmse_stats["se"],
                "rmse_delta_ci_high": rmse_stats["mean"] + 1.96 * rmse_stats["se"],
            }
        )

    pd.DataFrame(strategy_rows).to_csv(output_dir / "strategy_comparison.csv", index=False)
    pd.DataFrame(paired_rows).to_csv(output_dir / "paired_strategy_comparison.csv", index=False)


def run_misspecification(output_dir: Path, scale: Workload, seed: int) -> None:
    rng = np.random.default_rng(seed + 404)
    csv_rows: list[dict[str, float]] = []
    alpha_candidates = (0.05, 0.10, 0.20, 0.30, 0.40, 0.50)
    for true_alpha in alpha_candidates:
        hidden_high, informed_mask, customer_buys = make_order_tape(
            rng,
            true_alpha=true_alpha,
            episodes=scale.misspec_episodes,
            trades=scale.information_trades,
        )
        for assumed_alpha in alpha_candidates:
            metrics = simulate_information_batch(
                hidden_high=hidden_high,
                informed_mask=informed_mask,
                customer_buys=customer_buys,
                assumed_alpha=assumed_alpha,
                mode="bayesian",
            )
            pnl_stats = summarise(metrics["terminal_wealth"])
            csv_rows.append(
                {
                    "true_alpha": true_alpha,
                    "assumed_alpha": assumed_alpha,
                    "mean_pnl": pnl_stats["mean"],
                    "sd_pnl": pnl_stats["sd"],
                    "p05_pnl": pnl_stats["p05"],
                    "mean_fair_value_rmse": np.mean(metrics["rmse"]),
                    "mean_informed_flow_pnl": np.mean(metrics["informed_pnl"]),
                    "mean_noise_flow_pnl": np.mean(metrics["noise_pnl"]),
                    "mean_spread": np.mean(metrics["mean_spread"]),
                }
            )
    pd.DataFrame(csv_rows).to_csv(output_dir / "misspecification.csv", index=False)


def run_unknown_alpha(output_dir: Path, scale: Workload, seed: int) -> None:
    rng = np.random.default_rng(seed + 505)
    csv_rows: list[dict[str, float | str]] = []
    alpha_candidates = np.array([0.05, 0.10, 0.20, 0.30, 0.40, 0.50])
    for true_alpha in alpha_candidates:
        hidden_high, informed_mask, customer_buys = make_order_tape(
            rng,
            true_alpha=float(true_alpha),
            episodes=scale.unknown_alpha_episodes,
            trades=scale.discovery_trades,
        )
        candidates = (
            ("oracle", "bayesian", float(true_alpha)),
            ("fixed-0.20", "bayesian", 0.20),
            ("joint-bayes", "joint", 0.20),
        )
        for strategy_name, mode, assumed_alpha in candidates:
            metrics = simulate_information_batch(
                hidden_high=hidden_high,
                informed_mask=informed_mask,
                customer_buys=customer_buys,
                assumed_alpha=assumed_alpha,
                mode=mode,
                alpha_grid=alpha_candidates if mode == "joint" else None,
            )
            pnl_stats = summarise(metrics["terminal_wealth"])
            csv_rows.append(
                {
                    "true_alpha": true_alpha,
                    "strategy": strategy_name,
                    "mean_pnl": pnl_stats["mean"],
                    "sd_pnl": pnl_stats["sd"],
                    "p05_pnl": pnl_stats["p05"],
                    "mean_fair_value_rmse": np.mean(metrics["rmse"]),
                    "mean_alpha_estimate": np.mean(metrics["alpha_estimate"]),
                    "alpha_mae": np.mean(np.abs(metrics["alpha_estimate"] - true_alpha)),
                    "mean_spread": np.mean(metrics["mean_spread"]),
                }
            )
    pd.DataFrame(csv_rows).to_csv(output_dir / "unknown_alpha.csv", index=False)


def joint_snapshot_from_counts(
    buy_counts: np.ndarray,
    sell_counts: np.ndarray,
    alpha_candidates: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    alpha_row = alpha_candidates[None, :]
    buy_high = (1.0 + alpha_row) / 2.0
    buy_low = (1.0 - alpha_row) / 2.0

    high_log_weight = (
        buy_counts[:, None] * np.log(buy_high)
        + sell_counts[:, None] * np.log(1.0 - buy_high)
    )
    low_log_weight = (
        buy_counts[:, None] * np.log(buy_low)
        + sell_counts[:, None] * np.log(1.0 - buy_low)
    )
    shared_peak = np.maximum(np.max(high_log_weight, axis=1), np.max(low_log_weight, axis=1))
    high_mass = np.exp(high_log_weight - shared_peak[:, None])
    low_mass = np.exp(low_log_weight - shared_peak[:, None])
    evidence = np.sum(high_mass + low_mass, axis=1, keepdims=True)
    high_mass /= evidence
    low_mass /= evidence

    alpha_estimate = np.sum((high_mass + low_mass) * alpha_row, axis=1)

    buy_like_high = buy_high
    buy_like_low = buy_low
    sell_like_high = 1.0 - buy_high
    sell_like_low = 1.0 - buy_low
    ask_denominator = np.sum(high_mass * buy_like_high + low_mass * buy_like_low, axis=1)
    bid_denominator = np.sum(high_mass * sell_like_high + low_mass * sell_like_low, axis=1)
    ask = (
        HIGH_VALUE * np.sum(high_mass * buy_like_high, axis=1)
        + LOW_VALUE * np.sum(low_mass * buy_like_low, axis=1)
    ) / ask_denominator
    bid = (
        HIGH_VALUE * np.sum(high_mass * sell_like_high, axis=1)
        + LOW_VALUE * np.sum(low_mass * sell_like_low, axis=1)
    ) / bid_denominator
    return alpha_estimate, bid, ask


def first_stable_delay(
    alpha_path: np.ndarray,
    *,
    switch_after: int,
    target: float,
    tolerance: float = 0.10,
    stable_for: int = 5,
) -> int:
    for time_slot in range(switch_after + 1, alpha_path.size - stable_for + 1):
        if np.all(np.abs(alpha_path[time_slot : time_slot + stable_for] - target) <= tolerance):
            return time_slot - switch_after
    return -1


def run_regime_change(output_dir: Path, scale: Workload, seed: int) -> None:
    rng = np.random.default_rng(seed + 808)
    alpha_before, alpha_after = 0.05, 0.40
    switch_after = scale.regime_trades // 2
    alpha_candidates = np.array([0.05, 0.10, 0.20, 0.30, 0.40, 0.50])
    _, _, customer_buys = make_regime_tape(
        rng,
        episodes=scale.regime_paths,
        trades=scale.regime_trades,
        switch_after=switch_after,
        alpha_before=alpha_before,
        alpha_after=alpha_after,
    )
    cumulative_buys = np.concatenate(
        [
            np.zeros((scale.regime_paths, 1), dtype=np.int64),
            np.cumsum(customer_buys, axis=1, dtype=np.int64),
        ],
        axis=1,
    )

    curve_rows: list[dict[str, float | int | str]] = []
    adaptation_rows: list[dict[str, float | int | str]] = []
    filter_specs = (("full-history", 0), ("rolling-20", 20), ("rolling-50", 50), ("rolling-100", 100))

    for strategy_name, window in filter_specs:
        alpha_paths = np.empty((scale.regime_trades + 1, scale.regime_paths))
        spread_paths = np.empty_like(alpha_paths)
        for trade_no in range(scale.regime_trades + 1):
            window_start = 0 if window == 0 else max(0, trade_no - window)
            buy_counts = cumulative_buys[:, trade_no] - cumulative_buys[:, window_start]
            observations_seen = trade_no - window_start
            sell_counts = observations_seen - buy_counts
            alpha_estimate, bid, ask = joint_snapshot_from_counts(
                buy_counts,
                sell_counts,
                alpha_candidates,
            )
            alpha_paths[trade_no] = alpha_estimate
            spread_paths[trade_no] = ask - bid

            true_alpha = alpha_before if trade_no < switch_after else alpha_after
            curve_rows.append(
                {
                    "strategy": strategy_name,
                    "window": window,
                    "trade_no": trade_no,
                    "true_alpha": true_alpha,
                    "q25_alpha_estimate": np.quantile(alpha_estimate, 0.25),
                    "median_alpha_estimate": np.quantile(alpha_estimate, 0.50),
                    "q75_alpha_estimate": np.quantile(alpha_estimate, 0.75),
                    "median_spread": np.quantile(ask - bid, 0.50),
                }
            )

        delays = np.array(
            [
                first_stable_delay(
                    alpha_paths[:, path_no],
                    switch_after=switch_after,
                    target=alpha_after,
                )
                for path_no in range(scale.regime_paths)
            ]
        )
        reached = delays[delays >= 0]
        post_switch_mae = np.mean(
            np.abs(alpha_paths[switch_after + 1 :] - alpha_after),
            axis=0,
        )
        adaptation_rows.append(
            {
                "strategy": strategy_name,
                "window": window,
                "reach_rate": reached.size / scale.regime_paths,
                "mean_adaptation_delay": float(np.mean(reached)) if reached.size else np.nan,
                "median_adaptation_delay": float(np.median(reached)) if reached.size else np.nan,
                "mean_post_switch_alpha_mae": float(np.mean(post_switch_mae)),
            }
        )

    pd.DataFrame(curve_rows).to_csv(output_dir / "regime_change.csv", index=False)
    pd.DataFrame(adaptation_rows).to_csv(output_dir / "regime_adaptation.csv", index=False)


def simulate_inventory_batch(
    *,
    seed: int,
    episodes: int,
    steps: int,
    half_spread: float,
    inventory_skew: float,
) -> dict[str, np.ndarray]:
    rng = np.random.default_rng(seed)
    live_mid = np.full(episodes, 100.0)
    cash_balance = np.zeros(episodes)
    inventory_units = np.zeros(episodes, dtype=np.int64)
    max_abs_inventory = np.zeros(episodes, dtype=np.int64)
    absolute_inventory_total = np.zeros(episodes)
    fill_count = np.zeros(episodes, dtype=np.int64)

    for _market_step in range(steps):
        quote_centre = live_mid - inventory_skew * inventory_units
        bid = quote_centre - half_spread
        ask = quote_centre + half_spread
        customer_buys = rng.random(episodes) < 0.5
        quote_distance = np.where(customer_buys, ask - live_mid, live_mid - bid)
        fill_chance = np.minimum(1.0, 0.80 * np.exp(-1.10 * np.maximum(0.0, quote_distance)))
        got_filled = rng.random(episodes) < fill_chance

        cash_balance += np.where(got_filled & customer_buys, ask, 0.0)
        cash_balance -= np.where(got_filled & ~customer_buys, bid, 0.0)
        inventory_units += np.where(got_filled & customer_buys, -1, 0)
        inventory_units += np.where(got_filled & ~customer_buys, 1, 0)
        fill_count += got_filled
        max_abs_inventory = np.maximum(max_abs_inventory, np.abs(inventory_units))
        absolute_inventory_total += np.abs(inventory_units)
        live_mid += 0.45 * rng.standard_normal(episodes)

    return {
        "terminal_wealth": cash_balance + inventory_units * live_mid,
        "final_inventory": inventory_units,
        "max_abs_inventory": max_abs_inventory,
        "mean_abs_inventory": absolute_inventory_total / steps,
        "fill_count": fill_count,
    }


def run_inventory_tradeoff(output_dir: Path, scale: Workload, seed: int) -> None:
    csv_rows: list[dict[str, float]] = []
    for inventory_skew in (0.0, 0.02, 0.05, 0.10, 0.20, 0.35):
        batch = simulate_inventory_batch(
            seed=seed + 606,
            episodes=scale.inventory_episodes,
            steps=scale.inventory_steps,
            half_spread=0.75,
            inventory_skew=inventory_skew,
        )
        pnl_stats = summarise(batch["terminal_wealth"])
        csv_rows.append(
            {
                "inventory_skew": inventory_skew,
                "mean_pnl": pnl_stats["mean"],
                "sd_pnl": pnl_stats["sd"],
                "p05_pnl": pnl_stats["p05"],
                "median_pnl": pnl_stats["median"],
                "p95_pnl": pnl_stats["p95"],
                "mean_max_abs_inventory": np.mean(batch["max_abs_inventory"]),
                "mean_abs_inventory": np.mean(batch["mean_abs_inventory"]),
                "mean_fill_count": np.mean(batch["fill_count"]),
            }
        )
    pd.DataFrame(csv_rows).to_csv(output_dir / "inventory_tradeoff.csv", index=False)


def run_quote_distance(output_dir: Path, scale: Workload, seed: int) -> None:
    csv_rows: list[dict[str, float]] = []
    for half_spread in (0.10, 0.25, 0.50, 0.75, 1.00, 1.50, 2.00, 3.00):
        batch = simulate_inventory_batch(
            seed=seed + 707,
            episodes=scale.inventory_episodes,
            steps=scale.inventory_steps,
            half_spread=half_spread,
            inventory_skew=0.08,
        )
        pnl_stats = summarise(batch["terminal_wealth"])
        csv_rows.append(
            {
                "half_spread": half_spread,
                "mean_pnl": pnl_stats["mean"],
                "sd_pnl": pnl_stats["sd"],
                "p05_pnl": pnl_stats["p05"],
                "mean_fill_count": np.mean(batch["fill_count"]),
                "mean_max_abs_inventory": np.mean(batch["max_abs_inventory"]),
            }
        )
    pd.DataFrame(csv_rows).to_csv(output_dir / "quote_distance.csv", index=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the independent numerical parity implementation")
    parser.add_argument("--out", type=Path, default=Path("results/data"))
    parser.add_argument("--seed", type=int, default=20260831)
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    scale = choose_workload(args.quick)
    run_spread_validation(args.out, scale, args.seed)
    run_price_discovery(args.out, scale, args.seed)
    run_strategy_comparison(args.out, scale, args.seed)
    run_misspecification(args.out, scale, args.seed)
    run_unknown_alpha(args.out, scale, args.seed)
    run_regime_change(args.out, scale, args.seed)
    run_inventory_tradeoff(args.out, scale, args.seed)
    run_quote_distance(args.out, scale, args.seed)
    pd.DataFrame(
        [
            {"field": "seed", "value": args.seed},
            {"field": "profile", "value": "quick" if args.quick else "full"},
            {"field": "engine", "value": "python-parity"},
            {"field": "experiment_count", "value": 8},
        ]
    ).to_csv(args.out / "run_manifest.csv", index=False)
    print(f"wrote parity CSVs to {args.out}")


if __name__ == "__main__":
    main()
