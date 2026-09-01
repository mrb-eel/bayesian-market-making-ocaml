# Contributing

Keep changes small enough that their effect can be isolated. A modelling change should arrive with a test, a regenerated experiment, and an update to the paper or model notes when interpretation changes.

Before opening a pull request:

```bash
opam exec -- dune build @all
opam exec -- dune runtest
rm -rf results/tmp
opam exec -- dune exec bin/main.exe -- all --quick \
  --seed 20260831 \
  --out results/tmp
python analysis/check_outputs.py --input results/tmp
python analysis/plot_results.py \
  --input results/tmp \
  --output results/tmp/figures \
  --report-dir results/tmp/report
```

Do not commit `_build`, virtual environments, temporary output directories, or LaTeX auxiliary files.
