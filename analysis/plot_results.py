#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def save_figure(target_dir: Path, stem: str) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    plt.tight_layout()
    plt.savefig(target_dir / f"{stem}.pdf", bbox_inches="tight")
    plt.savefig(target_dir / f"{stem}.png", dpi=220, bbox_inches="tight")
    plt.close()


def spread_plot(csv_dir: Path, figure_dir: Path) -> None:
    spread_frame = pd.read_csv(csv_dir / "spread_validation.csv")
    plt.figure(figsize=(7.2, 4.5))
    plt.plot(
        spread_frame["alpha"],
        spread_frame["theoretical_spread"],
        label="Analytical spread",
        linewidth=2,
    )
    plt.scatter(
        spread_frame["alpha"],
        spread_frame["simulated_spread"],
        label="Monte Carlo estimate",
        zorder=3,
    )
    plt.xlabel(r"Informed-trader probability $\alpha$")
    plt.ylabel("Bid-ask spread")
    plt.title("Analytical and simulated informational spread")
    plt.legend(frameon=False)
    save_figure(figure_dir, "01_spread_validation")


def discovery_plot(csv_dir: Path, figure_dir: Path) -> None:
    discovery_frame = pd.read_csv(csv_dir / "price_discovery.csv")
    plt.figure(figsize=(7.2, 4.5))
    for alpha, alpha_slice in discovery_frame.groupby("alpha"):
        plt.plot(
            alpha_slice["trade_no"],
            alpha_slice["median_correct_confidence"],
            label=fr"$\alpha={alpha:.2f}$",
        )
        plt.fill_between(
            alpha_slice["trade_no"],
            alpha_slice["q25_correct_confidence"],
            alpha_slice["q75_correct_confidence"],
            alpha=0.14,
        )
    plt.axhline(0.95, linestyle="--", linewidth=1, label="95% confidence")
    plt.xlabel("Observed trades")
    plt.ylabel("Posterior probability assigned to the true state")
    plt.ylim(0.45, 1.01)
    plt.title("Price discovery from order direction")
    plt.legend(frameon=False)
    save_figure(figure_dir, "02_price_discovery")


def strategy_plots(csv_dir: Path, figure_dir: Path) -> None:
    comparison = pd.read_csv(csv_dir / "strategy_comparison.csv")
    rmse_pivot = comparison.pivot(
        index="true_alpha",
        columns="strategy",
        values="mean_fair_value_rmse",
    )
    plt.figure(figsize=(7.2, 4.5))
    for strategy_name in rmse_pivot.columns:
        plt.plot(
            rmse_pivot.index,
            rmse_pivot[strategy_name],
            marker="o",
            label=strategy_name.replace("-", " ").title(),
        )
    plt.xlabel(r"True informed-trader probability $\alpha$")
    plt.ylabel("Fair-value RMSE")
    plt.title("Belief updating reduces estimation error")
    plt.legend(frameon=False)
    save_figure(figure_dir, "03_strategy_rmse")

    pnl_pivot = comparison.pivot(index="true_alpha", columns="strategy", values="sd_pnl")
    plt.figure(figsize=(7.2, 4.5))
    for strategy_name in pnl_pivot.columns:
        plt.plot(
            pnl_pivot.index,
            pnl_pivot[strategy_name],
            marker="o",
            label=strategy_name.replace("-", " ").title(),
        )
    plt.xlabel(r"True informed-trader probability $\alpha$")
    plt.ylabel("Standard deviation of terminal P&L")
    plt.title("P&L dispersion under static and Bayesian quoting")
    plt.legend(frameon=False)
    save_figure(figure_dir, "04_strategy_pnl_dispersion")

    paired = pd.read_csv(csv_dir / "paired_strategy_comparison.csv")
    lower_error = paired["mean_rmse_delta"] - paired["rmse_delta_ci_low"]
    upper_error = paired["rmse_delta_ci_high"] - paired["mean_rmse_delta"]
    plt.figure(figsize=(7.2, 4.5))
    plt.errorbar(
        paired["true_alpha"],
        paired["mean_rmse_delta"],
        yerr=np.vstack([lower_error, upper_error]),
        marker="o",
        capsize=4,
    )
    plt.axhline(0.0, linestyle="--", linewidth=1)
    plt.xlabel(r"True informed-trader probability $\alpha$")
    plt.ylabel("Paired RMSE difference: Bayesian - static")
    plt.title("Paired comparison on identical order tapes")
    save_figure(figure_dir, "05_paired_rmse_difference")


def heatmap(
    frame: pd.DataFrame,
    *,
    value_column: str,
    title: str,
    label: str,
    stem: str,
    figure_dir: Path,
) -> None:
    matrix = frame.pivot(index="true_alpha", columns="assumed_alpha", values=value_column)
    plt.figure(figsize=(6.5, 5.1))
    image = plt.imshow(matrix.values, origin="lower", aspect="auto")
    plt.colorbar(image, label=label)
    plt.xticks(np.arange(matrix.columns.size), [f"{value:.2f}" for value in matrix.columns])
    plt.yticks(np.arange(matrix.index.size), [f"{value:.2f}" for value in matrix.index])
    plt.xlabel(r"Assumed $\widehat{\alpha}$")
    plt.ylabel(r"True $\alpha$")
    plt.title(title)
    for row_slot in range(matrix.shape[0]):
        for column_slot in range(matrix.shape[1]):
            plt.text(
                column_slot,
                row_slot,
                f"{matrix.values[row_slot, column_slot]:.1f}",
                ha="center",
                va="center",
                fontsize=7,
            )
    save_figure(figure_dir, stem)


def misspecification_plots(csv_dir: Path, figure_dir: Path) -> None:
    misspec = pd.read_csv(csv_dir / "misspecification.csv")
    heatmap(
        misspec,
        value_column="mean_fair_value_rmse",
        title="Fair-value error under model misspecification",
        label="Mean RMSE",
        stem="06_misspecification_rmse",
        figure_dir=figure_dir,
    )
    heatmap(
        misspec,
        value_column="mean_pnl",
        title="Terminal P&L under model misspecification",
        label="Mean terminal P&L",
        stem="07_misspecification_pnl",
        figure_dir=figure_dir,
    )


def unknown_alpha_plots(csv_dir: Path, figure_dir: Path) -> None:
    unknown = pd.read_csv(csv_dir / "unknown_alpha.csv")
    plt.figure(figsize=(7.2, 4.5))
    for strategy_name, strategy_slice in unknown.groupby("strategy"):
        plt.plot(
            strategy_slice["true_alpha"],
            strategy_slice["mean_fair_value_rmse"],
            marker="o",
            label=strategy_name.replace("-", " ").title(),
        )
    plt.xlabel(r"True $\alpha$")
    plt.ylabel("Fair-value RMSE")
    plt.title("Known, fixed, and jointly inferred information intensity")
    plt.legend(frameon=False)
    save_figure(figure_dir, "08_unknown_alpha_rmse")

    joint = unknown[unknown["strategy"] == "joint-bayes"]
    plt.figure(figsize=(7.2, 4.5))
    plt.plot(
        joint["true_alpha"],
        joint["mean_alpha_estimate"],
        marker="o",
        label="Posterior mean",
    )
    plt.plot(
        joint["true_alpha"],
        joint["true_alpha"],
        linestyle="--",
        label="Perfect calibration",
    )
    plt.xlabel(r"True $\alpha$")
    plt.ylabel(r"Mean terminal estimate of $\alpha$")
    plt.title("Calibration of the joint Bayesian filter")
    plt.legend(frameon=False)
    save_figure(figure_dir, "09_alpha_calibration")


def regime_plots(csv_dir: Path, figure_dir: Path) -> None:
    regime_frame = pd.read_csv(csv_dir / "regime_change.csv")
    plt.figure(figsize=(7.5, 4.7))
    for strategy_name, strategy_slice in regime_frame.groupby("strategy"):
        plt.plot(
            strategy_slice["trade_no"],
            strategy_slice["median_alpha_estimate"],
            label=strategy_name.replace("-", " ").title(),
        )
    truth = regime_frame[regime_frame["strategy"] == "full-history"]
    plt.step(
        truth["trade_no"],
        truth["true_alpha"],
        where="post",
        linestyle="--",
        linewidth=2,
        label="True regime",
    )
    plt.xlabel("Observed trades")
    plt.ylabel(r"Median estimate of $\alpha$")
    plt.title("Adaptation after an information-regime change")
    plt.legend(frameon=False, ncol=2)
    save_figure(figure_dir, "10_regime_alpha_estimate")

    adaptation = pd.read_csv(csv_dir / "regime_adaptation.csv")
    plt.figure(figsize=(7.2, 4.5))
    readable_names = adaptation["strategy"].str.replace("-", " ").str.title()
    plt.bar(readable_names, adaptation["mean_post_switch_alpha_mae"])
    plt.ylabel(r"Mean post-switch absolute error in $\alpha$")
    plt.title("Shorter windows adapt faster but discard evidence")
    plt.xticks(rotation=15, ha="right")
    save_figure(figure_dir, "11_regime_post_switch_error")


def inventory_plots(csv_dir: Path, figure_dir: Path) -> None:
    inventory = pd.read_csv(csv_dir / "inventory_tradeoff.csv")
    plt.figure(figsize=(7.2, 4.5))
    plt.plot(
        inventory["inventory_skew"],
        inventory["mean_max_abs_inventory"],
        marker="o",
    )
    plt.xlabel(r"Inventory-skew coefficient $\beta$")
    plt.ylabel("Mean maximum absolute inventory")
    plt.title("Inventory skew limits position accumulation")
    save_figure(figure_dir, "12_inventory_exposure")

    plt.figure(figsize=(7.2, 4.5))
    plt.plot(
        inventory["inventory_skew"],
        inventory["mean_pnl"],
        marker="o",
        label="Mean P&L",
    )
    plt.plot(
        inventory["inventory_skew"],
        inventory["p05_pnl"],
        marker="o",
        label="5th percentile P&L",
    )
    plt.xlabel(r"Inventory-skew coefficient $\beta$")
    plt.ylabel("Terminal P&L")
    plt.title("Inventory control changes the P&L distribution")
    plt.legend(frameon=False)
    save_figure(figure_dir, "13_inventory_pnl")


def quote_distance_plots(csv_dir: Path, figure_dir: Path) -> None:
    quote_distance = pd.read_csv(csv_dir / "quote_distance.csv")
    plt.figure(figsize=(7.2, 4.5))
    plt.plot(quote_distance["half_spread"], quote_distance["mean_pnl"], marker="o")
    plt.xlabel(r"Half-spread $\delta$")
    plt.ylabel("Mean terminal P&L")
    plt.title("A wider quote is not always more profitable")
    save_figure(figure_dir, "14_quote_distance_pnl")

    plt.figure(figsize=(7.2, 4.5))
    plt.plot(
        quote_distance["half_spread"],
        quote_distance["mean_fill_count"],
        marker="o",
    )
    plt.xlabel(r"Half-spread $\delta$")
    plt.ylabel("Mean fills per episode")
    plt.title("Execution falls as quotes move away from the midprice")
    save_figure(figure_dir, "15_quote_distance_fills")


def latex_command(name: str, value: str) -> str:
    return rf"\newcommand{{\{name}}}{{{value}}}"


def write_report_assets(csv_dir: Path, report_dir: Path) -> None:
    spread = pd.read_csv(csv_dir / "spread_validation.csv")
    comparison = pd.read_csv(csv_dir / "strategy_comparison.csv")
    paired = pd.read_csv(csv_dir / "paired_strategy_comparison.csv")
    hits = pd.read_csv(csv_dir / "price_discovery_hitting.csv")
    misspec = pd.read_csv(csv_dir / "misspecification.csv")
    unknown = pd.read_csv(csv_dir / "unknown_alpha.csv")
    regime = pd.read_csv(csv_dir / "regime_adaptation.csv")
    inventory = pd.read_csv(csv_dir / "inventory_tradeoff.csv")
    distance = pd.read_csv(csv_dir / "quote_distance.csv")
    manifest = pd.read_csv(csv_dir / "run_manifest.csv").set_index("field")["value"]

    spread_error = np.max(np.abs(spread["simulated_spread"] - spread["theoretical_spread"]))
    at_twenty = comparison[comparison["true_alpha"] == 0.20].set_index("strategy")
    paired_twenty = paired[paired["true_alpha"] == 0.20].iloc[0]
    rmse_drop = 100 * (
        1
        - at_twenty.loc["bayesian", "mean_fair_value_rmse"]
        / at_twenty.loc["static", "mean_fair_value_rmse"]
    )
    sd_drop = 100 * (
        1 - at_twenty.loc["bayesian", "sd_pnl"] / at_twenty.loc["static", "sd_pnl"]
    )
    hit_20 = hits[(hits["alpha"] == 0.20) & (hits["threshold"] == 0.95)].iloc[0]
    hit_40 = hits[(hits["alpha"] == 0.40) & (hits["threshold"] == 0.95)].iloc[0]
    misspec_cell = misspec[
        (misspec["true_alpha"] == 0.40) & (misspec["assumed_alpha"] == 0.20)
    ].iloc[0]
    correct_cell = misspec[
        (misspec["true_alpha"] == 0.40) & (misspec["assumed_alpha"] == 0.40)
    ].iloc[0]
    joint = unknown[unknown["strategy"] == "joint-bayes"]
    mean_alpha_mae = joint["alpha_mae"].mean()
    full_history = regime[regime["strategy"] == "full-history"].iloc[0]
    rolling_twenty = regime[regime["strategy"] == "rolling-20"].iloc[0]
    flat_inventory = inventory[inventory["inventory_skew"] == 0.0].iloc[0]
    skew_inventory = inventory[inventory["inventory_skew"] == 0.10].iloc[0]
    inventory_drop = 100 * (
        1
        - skew_inventory["mean_max_abs_inventory"]
        / flat_inventory["mean_max_abs_inventory"]
    )
    risk_drop = 100 * (1 - skew_inventory["sd_pnl"] / flat_inventory["sd_pnl"])
    mean_pnl_drop = 100 * (
        1 - skew_inventory["mean_pnl"] / flat_inventory["mean_pnl"]
    )
    best_quote = distance.loc[distance["mean_pnl"].idxmax()]

    commands = [
        latex_command("SpreadMaxError", f"{spread_error:.3f}"),
        latex_command("RmseDropAtTwenty", f"{rmse_drop:.1f}\\%"),
        latex_command("PnlSdDropAtTwenty", f"{sd_drop:.1f}\\%"),
        latex_command("MedianHitTwenty", f"{hit_20['median_hitting_time']:.0f}"),
        latex_command("MedianHitForty", f"{hit_40['median_hitting_time']:.0f}"),
        latex_command("PairedRmseDeltaTwenty", f"{paired_twenty['mean_rmse_delta']:.2f}"),
        latex_command("PairedRmseCiLow", f"{paired_twenty['rmse_delta_ci_low']:.2f}"),
        latex_command("PairedRmseCiHigh", f"{paired_twenty['rmse_delta_ci_high']:.2f}"),
        latex_command("MisspecPnl", f"{misspec_cell['mean_pnl']:.2f}"),
        latex_command("CorrectPnl", f"{correct_cell['mean_pnl']:.2f}"),
        latex_command("MisspecRmse", f"{misspec_cell['mean_fair_value_rmse']:.2f}"),
        latex_command("CorrectRmse", f"{correct_cell['mean_fair_value_rmse']:.2f}"),
        latex_command("JointAlphaMae", f"{mean_alpha_mae:.3f}"),
        latex_command("RollingReachRate", f"{100 * rolling_twenty['reach_rate']:.1f}\\%"),
        latex_command("RollingMedianDelay", f"{rolling_twenty['median_adaptation_delay']:.0f}"),
        latex_command("RollingPostMae", f"{rolling_twenty['mean_post_switch_alpha_mae']:.3f}"),
        latex_command("FullHistoryReachRate", f"{100 * full_history['reach_rate']:.1f}\\%"),
        latex_command("FullHistoryPostMae", f"{full_history['mean_post_switch_alpha_mae']:.3f}"),
        latex_command("InventoryExposureDrop", f"{inventory_drop:.1f}\\%"),
        latex_command("InventoryRiskDrop", f"{risk_drop:.1f}\\%"),
        latex_command("InventoryMeanPnlDrop", f"{mean_pnl_drop:.1f}\\%"),
        latex_command("BestHalfSpread", f"{best_quote['half_spread']:.2f}"),
        latex_command("BestHalfSpreadPnl", f"{best_quote['mean_pnl']:.2f}"),
        latex_command("BestHalfSpreadFills", f"{best_quote['mean_fill_count']:.1f}"),
        latex_command("ResultsEngine", str(manifest.get("engine", "unspecified")).replace("-", "--")),
        latex_command("ResultsProfile", str(manifest.get("profile", "unspecified"))),
        latex_command("ResultsSeed", str(manifest.get("seed", "unspecified"))),
    ]
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "results_macros.tex").write_text(
        "\n".join(commands) + "\n",
        encoding="utf-8",
    )

    table_rows = []
    for alpha in (0.05, 0.20, 0.40):
        static = comparison[
            (comparison["true_alpha"] == alpha) & (comparison["strategy"] == "static")
        ].iloc[0]
        bayesian = comparison[
            (comparison["true_alpha"] == alpha) & (comparison["strategy"] == "bayesian")
        ].iloc[0]
        table_rows.append(
            f"{alpha:.2f} & {static['mean_fair_value_rmse']:.2f} & "
            f"{bayesian['mean_fair_value_rmse']:.2f} & {static['sd_pnl']:.2f} & "
            f"{bayesian['sd_pnl']:.2f} \\\\"
        )
    table_macro = "\\newcommand{\\StrategyRows}{%\n" + "\n".join(table_rows) + "\n}\n"
    (report_dir / "strategy_table_rows.tex").write_text(table_macro, encoding="utf-8")

    regime_rows = []
    for _, regime_row in regime.iterrows():
        median_delay = (
            "--" if pd.isna(regime_row["median_adaptation_delay"]) else f"{regime_row['median_adaptation_delay']:.0f}"
        )
        regime_rows.append(
            f"{regime_row['strategy'].replace('-', ' ')} & {100 * regime_row['reach_rate']:.1f}\\% & "
            f"{median_delay} & {regime_row['mean_post_switch_alpha_mae']:.3f} \\\\"
        )
    regime_macro = "\\newcommand{\\RegimeRows}{%\n" + "\n".join(regime_rows) + "\n}\n"
    (report_dir / "regime_table_rows.tex").write_text(regime_macro, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create figures and LaTeX result fragments")
    parser.add_argument("--input", type=Path, default=Path("results/data"))
    parser.add_argument("--output", type=Path, default=Path("results/figures"))
    parser.add_argument("--report-dir", type=Path, default=Path("report"))
    args = parser.parse_args()

    spread_plot(args.input, args.output)
    discovery_plot(args.input, args.output)
    strategy_plots(args.input, args.output)
    misspecification_plots(args.input, args.output)
    unknown_alpha_plots(args.input, args.output)
    regime_plots(args.input, args.output)
    inventory_plots(args.input, args.output)
    quote_distance_plots(args.input, args.output)
    write_report_assets(args.input, args.report_dir)
    print(f"wrote figures to {args.output}")


if __name__ == "__main__":
    main()
