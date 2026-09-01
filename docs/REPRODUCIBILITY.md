# Reproducibility and Numerical Provenance

## Two implementations, one model specification

The repository contains two independent numerical paths.

- `lib/` and `bin/` contain the primary OCaml implementation.
- `analysis/reference_runner.py` repeats the model in NumPy without calling, wrapping, or parsing the OCaml executable.

The second implementation is not a replacement for the first. It is a cross-check against errors that often survive ordinary unit testing: conditioning the bid on the wrong event, reversing customer-side inventory signs, updating a posterior before the trade that reveals the information, or aggregating paired experiments incorrectly.

Every output directory contains `run_manifest.csv`. The `engine` row identifies the program that generated those files. The checked-in reference outputs use:

```text
seed:             20260831
profile:          full
engine:           python-parity
experiment_count: 8
```

The environment used to assemble this release did not contain OCaml, opam, or Dune, and external package installation was unavailable. The OCaml source was therefore reviewed statically here, while the full numerical run was executed through the independent NumPy implementation. The LaTeX paper was compiled from those outputs and visually checked page by page. This distinction is retained in the manifest and in the paper rather than being inferred from the repository's primary language.

## Deterministic inputs

All experiment entry points accept an explicit integer seed. Each experiment uses a separate salt or substream, so changing the workload of one experiment does not silently alter the random stream used by another.

Strategy comparisons use common random numbers. A hidden state and order tape are generated once, then replayed against each competing strategy. Inventory comparisons likewise initialise each coefficient or spread choice with the same episode-indexed seeds. This does not remove Monte Carlo error, but it substantially reduces noise in pairwise differences.

## Workload profiles

The executable supports two profiles.

### Full

Used for the checked-in tables, figures, and report:

- 100,000 one-trade trials per spread-validation point;
- 3,000 price-discovery paths;
- 6,000 paired strategy episodes per information level;
- 1,800 episodes per misspecification cell;
- 2,500 episodes per unknown-alpha strategy and state;
- 800 regime-change paths;
- 3,500 inventory episodes per coefficient or quote distance.

### Quick

Used by continuous integration. It preserves every code path and output schema while reducing the number and length of episodes. Output validation relaxes only the confidence-interval condition that would be unreasonable at the smaller sample size; analytical identities, probability bounds, accounting reconciliation, and qualitative monotonicity checks remain active.

## End-to-end OCaml run

From a clean clone:

```bash
opam switch create . 5.2.1
opam install . --deps-only --with-test
opam exec -- dune build @all
opam exec -- dune runtest
opam exec -- dune exec bin/main.exe -- all \
  --seed 20260831 \
  --out results/data
```

Validate and render the outputs:

```bash
python -m pip install -r analysis/requirements.txt
python analysis/check_outputs.py --input results/data
python analysis/plot_results.py \
  --input results/data \
  --output results/figures \
  --report-dir report
```

Compile the paper twice so cross-references settle:

```bash
cd report
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
cp main.pdf Bayesian_Market_Making_Report.pdf
```

The shell and PowerShell scripts perform this complete sequence and stop on the first failed command.

## Independent parity run

To regenerate the checked-in style of reference output without using the OCaml executable:

```bash
python analysis/reference_runner.py \
  --seed 20260831 \
  --out results/data
python analysis/check_outputs.py --input results/data
python analysis/plot_results.py \
  --input results/data \
  --output results/figures \
  --report-dir report
```

The Python and OCaml random-number generators are not expected to produce byte-identical Monte Carlo samples. Agreement is assessed through the analytical formula, signs, ranges, paired direction of effects, and broad numerical stability rather than exact row-by-row equality.

## Output checks

`analysis/check_outputs.py` rejects an output directory when any of the following fail:

- all expected files and manifest fields are present;
- numeric columns contain finite values except explicitly permitted missing hitting times;
- the simulated informational spread stays close to the closed form;
- posterior summaries remain inside their probability support;
- Bayesian fair-value RMSE is lower than the static baseline at every tested information level;
- paired RMSE differences have the expected sign;
- full-run paired confidence intervals exclude zero;
- total P&L reconciles with informed-flow plus noise-flow attribution;
- the misspecification grid has exactly one row per parameter pair;
- estimated alpha remains inside the candidate grid;
- the rolling regime estimator improves post-switch error relative to the full-history filter;
- inventory skew reduces maximum position exposure;
- fill counts decrease as quotes move farther away;
- the best tested quote distance is not a grid boundary.

The checks are deliberately broader than unit tests. A program can compile and still generate a polished but invalid dataset.

## Continuous integration

The main GitHub Actions workflow has two jobs.

1. The OCaml job installs OCaml 5.2.1, builds all targets, runs the 23-test suite, executes the quick experiment profile, validates the new CSV files, regenerates the figures and LaTeX fragments, and compiles the report.
2. The parity job runs the independent NumPy implementation with the quick profile and validates its outputs separately.

A second workflow, `full-reproduction`, is manually triggered. It runs the complete OCaml workload, validates every output, rebuilds the report, records checksums, and uploads the resulting release directory.

Generated CI artefacts are uploaded for inspection. A green workflow establishes that the repository builds from a clean Linux environment and that both numerical paths satisfy the stated invariants; it does not establish the empirical realism of the model.

## Interpretation policy

Results should be described with the engine and workload that produced them. In particular:

- `engine=ocaml` supports the phrase “generated by the OCaml simulator”;
- `engine=python-parity` supports “generated by the independent parity implementation of the model”;
- neither engine supports a claim of live trading performance;
- changing model assumptions requires rerunning the experiments and rebuilding the paper, not merely editing prose around old figures.

The model's limitations are part of its result. The provenance rules are intended to keep that principle visible in the software as well as the report.
