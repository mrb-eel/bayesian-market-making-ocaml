#!/usr/bin/env bash
set -euo pipefail

seed="${SEED:-20260831}"
python_cmd="${PYTHON:-python3}"

opam exec -- dune build @all
opam exec -- dune runtest
opam exec -- dune exec bin/main.exe -- all --seed "$seed" --out results/data

"$python_cmd" analysis/check_outputs.py --input results/data
"$python_cmd" analysis/plot_results.py \
  --input results/data \
  --output results/figures \
  --report-dir report

(
  cd report
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
)
cp report/main.pdf report/Bayesian_Market_Making_Report.pdf

printf '\nReproduction complete.\n'
printf 'CSV files: results/data\n'
printf 'Figures:   results/figures\n'
printf 'Paper:     report/Bayesian_Market_Making_Report.pdf\n'
