.PHONY: build test quick experiments validate figures report reproduce parity parity-quick clean

SEED ?= 20260831
PYTHON ?= python3

build:
	opam exec -- dune build @all

test:
	opam exec -- dune runtest

quick: build test
	rm -rf results/tmp
	opam exec -- dune exec bin/main.exe -- all --quick --seed $(SEED) --out results/tmp
	$(PYTHON) analysis/check_outputs.py --input results/tmp

experiments: build test
	opam exec -- dune exec bin/main.exe -- all --seed $(SEED) --out results/data

validate:
	$(PYTHON) analysis/check_outputs.py --input results/data

figures:
	$(PYTHON) analysis/plot_results.py --input results/data --output results/figures --report-dir report

report:
	cd report && pdflatex -interaction=nonstopmode -halt-on-error main.tex
	cd report && pdflatex -interaction=nonstopmode -halt-on-error main.tex
	cp report/main.pdf report/Bayesian_Market_Making_Report.pdf

reproduce: experiments validate figures report

parity:
	$(PYTHON) analysis/reference_runner.py --seed $(SEED) --out results/data
	$(PYTHON) analysis/check_outputs.py --input results/data
	$(MAKE) figures report

parity-quick:
	rm -rf results/tmp
	$(PYTHON) analysis/reference_runner.py --quick --seed $(SEED) --out results/tmp
	$(PYTHON) analysis/check_outputs.py --input results/tmp

clean:
	-opam exec -- dune clean
	rm -rf results/tmp _ci
	rm -f report/*.aux report/*.log report/*.out report/*.toc report/*.fls report/*.fdb_latexmk report/main.pdf
