# Bayesian Market Making in OCaml

[![CI](https://github.com/mrb-eel/bayesian-market-making-ocaml/actions/workflows/ci.yml/badge.svg)](https://github.com/mrb-eel/bayesian-market-making-ocaml/actions/workflows/ci.yml)

A reproducible computational study of market making under adverse selection. The project starts from a binary Glosten-Milgrom-style information model, derives competitive quotes analytically, and then uses simulation to study sequential Bayesian learning, parameter misspecification, unknown information intensity, regime change, and inventory risk.

The primary numerical engine is written in OCaml. A separate NumPy implementation repeats the model equations as an independent cross-check.

The project is a research and software study. It does not claim live-market profitability, empirical calibration, or a production trading strategy.

## Paper

**Bayesian Learning and Model Risk in a Binary Market-Making Model**  
*A Reproducible Computational Note on Adverse Selection, Misspecification, and Regime Change*

[Read the current PDF](report/Bayesian_Market_Making_Report.pdf)

Research status: technical report, not peer reviewed.

## Core model

The terminal value is binary,

\[
V \in \{L,H\}, \qquad P(V=H)=p.
\]

Each arriving trader is informed with probability \(\alpha\). An informed trader buys in the high state and sells in the low state. A noise trader buys or sells with equal probability. Therefore,

\[
P(Buy\mid H)=\frac{1+\alpha}{2}, \qquad
P(Buy\mid L)=\frac{1-\alpha}{2}.
\]

The competitive ask and bid are conditional expectations of terminal value given the side that trades. For a general prior \(p\),

\[
A=L+(H-L)\frac{p(1+\alpha)}{1+\alpha(2p-1)},
\]

\[
B=L+(H-L)\frac{p(1-\alpha)}{1-\alpha(2p-1)}.
\]

Hence

\[
A-B=(H-L)\frac{4\alpha p(1-p)}{1-\alpha^2(2p-1)^2}.
\]

At the symmetric prior \(p=1/2\), this reduces to

\[
A-B=(H-L)\alpha.
\]

With \(L=90\), \(H=110\), and \(\alpha=0.20\), the initial quote is `98 / 102`.

Order flow updates the posterior in log-odds space. One buy adds

\[
\lambda=\log\frac{1+\alpha}{1-\alpha}
\]

to the log odds of the high state, while one sell subtracts the same amount. Under the high state, the expected log-odds drift per trade is \(\alpha\lambda\). This gives an analytical explanation for the faster price discovery seen at larger values of \(\alpha\).

A second benchmark makes the misspecification experiment easier to interpret. If the true informed fraction is \(\alpha\), the market maker quotes using \(\widehat{\alpha}\), the prior \(p\) is otherwise correct, and every incoming order executes, then expected P&L on the next trade is

\[
E[\Pi_1]=(H-L)\frac{2p(1-p)(\widehat{\alpha}-\alpha)}{1-\widehat{\alpha}^2(2p-1)^2}.
\]

At \(p=1/2\), this becomes \(E[\Pi_1]=(H-L)(\widehat{\alpha}-\alpha)/2\). Positive P&L from overestimating \(\alpha\) is therefore partly mechanical in the forced-execution model; wider quotes do not lose flow.

## What is tested

The repository studies eight groups of experiments:

1. analytical spread validation against Monte Carlo conditional values;
2. Bayesian price discovery from customer-side order direction;
3. static versus sequential Bayesian quoting on identical order tapes;
4. misspecification of the informed-trader probability;
5. joint inference of terminal value and information intensity;
6. adaptation after an abrupt change in information intensity;
7. inventory skew in a separate quote-sensitive execution model;
8. the spread-volume trade-off once fill probability depends on quote distance.

The information and inventory environments are kept separate deliberately. In the information model, one order executes at every step, so changing the quote cannot change volume. Inventory control is only evaluated after a separate execution mechanism makes fills respond to price.

## Reference run

The checked-in reference results use seed `20260831`, profile `full`, and engine `ocaml`.

| Experiment | Reference observation |
| --- | --- |
| Spread validation | Maximum absolute theory-simulation gap: `0.087` price units |
| Price discovery | Median time to 95% confidence: 28 trades at `alpha = 0.20`, 8 at `alpha = 0.40` |
| Static vs Bayesian | At `alpha = 0.20`, Bayesian updating lowers fair-value RMSE by `40.7%` and terminal P&L standard deviation by `61.1%` |
| Paired comparison | Mean Bayesian-minus-static RMSE difference at `alpha = 0.20`: `-4.07`, with a 95% Monte Carlo interval of `[-4.15, -3.99]` |
| Misspecification | True `alpha = 0.40`, assumed `0.20`: mean terminal P&L `-19.09`; correct specification: `0.41` |
| Unknown alpha | Mean absolute error of the joint posterior mean: `0.067` |
| Regime change | A 20-trade rolling filter adapts on `99.1%` of paths with median delay 17 trades; the full-history filter adapts on `13.0%` |
| Inventory skew | Increasing the skew coefficient from `0` to `0.10` reduces mean maximum inventory by `56.8%` and P&L volatility by `68.3%`, while mean P&L falls by `3.9%` |
| Quote distance | Mean P&L peaks at a half-spread of `1.00` in the stated toy execution model |

These are simulation results under explicit assumptions. The misspecification P&L surface is particularly sensitive to exogenous execution, because excessively wide quotes do not lose flow in the information model.

## Reproducibility

The repository uses several independent checks:

- hidden state and trader identity are generated outside the strategy interface;
- quotes are formed before the current order direction is observed;
- competing strategies receive the same order tapes;
- random seeds and workload profiles are recorded in `run_manifest.csv`;
- terminal cash plus marked inventory reconciles with trade-level economic P&L;
- the analytical spread acts as a numerical oracle;
- a NumPy implementation independently repeats the model equations;
- output checks reject malformed or economically inconsistent results;
- GitHub Actions rebuilds, tests, simulates, validates, plots, and compiles the report from a clean environment.

See [REPRODUCIBILITY.md](REPRODUCIBILITY.md) for the full provenance policy.

## Build and test

The project targets OCaml 5.2.1 and is compatible with OCaml 4.14 or newer.

```bash
opam switch create . 5.2.1
opam install . --deps-only --with-test
opam exec -- dune build @all
opam exec -- dune runtest
```

Run the complete OCaml experiment suite:

```bash
opam exec -- dune exec bin/main.exe -- all \
  --seed 20260831 \
  --out results/data
```

Use `--quick` for the reduced CI workload.

Validate the data, rebuild figures, and generate the LaTeX fragments:

```bash
python -m pip install -r analysis/requirements.txt
python analysis/check_outputs.py --input results/data
python analysis/plot_results.py \
  --input results/data \
  --output results/figures \
  --report-dir report
```

Compile the paper:

```bash
cd report
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Platform scripts are also provided:

```bash
./scripts/reproduce.sh
```

```powershell
.\scripts\reproduce.ps1
```

## Repository map

```text
.
├── lib/                         Core OCaml model and simulators
├── bin/main.ml                  Command-line entry point
├── test/test_suite.ml           Model, accounting, and regression tests
├── analysis/
│   ├── reference_runner.py      Independent NumPy implementation
│   ├── check_outputs.py         Output and invariant validation
│   └── plot_results.py          Figures and generated LaTeX fragments
├── results/
│   ├── data/                    Reference-run CSV files
│   └── figures/                 Generated figures
├── report/
│   ├── main.tex                 Paper source
│   └── Bayesian_Market_Making_Report.pdf
├── docs/
│   └── MODEL_NOTES.md
├── REPRODUCIBILITY.md
├── CITATION.cff
└── .github/workflows/
```

## Model boundaries

The information model uses a binary terminal value, perfectly informed informed traders, balanced unit-size noise flow, one market maker, and exogenous execution. It has no queue position, tick size, latency, fees, competing venue, hedging instrument, or strategic order splitting.

The inventory environment uses a Gaussian public midprice and an imposed exponential fill curve. Its parameters are not calibrated to market data. Information risk and inventory risk are not solved in one equilibrium.

These boundaries are part of the result. The project is designed to make assumptions easy to inspect rather than to make the simulator look realistic by adding mechanisms that cannot be separately identified.

## Citation

Citation metadata is provided in [`CITATION.cff`](CITATION.cff). Once a versioned software release has been archived, the release DOI should be added there.

## License

MIT. See [LICENSE](LICENSE).
