$ErrorActionPreference = "Stop"

$seed = if ($env:SEED) { $env:SEED } else { "20260831" }
$python = if ($env:PYTHON) { $env:PYTHON } else { "python" }

opam exec -- dune build @all
if ($LASTEXITCODE -ne 0) { throw "OCaml build failed" }

opam exec -- dune runtest
if ($LASTEXITCODE -ne 0) { throw "OCaml tests failed" }

opam exec -- dune exec bin/main.exe -- all --seed $seed --out results/data
if ($LASTEXITCODE -ne 0) { throw "Experiment run failed" }

& $python analysis/check_outputs.py --input results/data
if ($LASTEXITCODE -ne 0) { throw "Output validation failed" }

& $python analysis/plot_results.py `
  --input results/data `
  --output results/figures `
  --report-dir report
if ($LASTEXITCODE -ne 0) { throw "Figure generation failed" }

Push-Location report
try {
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  if ($LASTEXITCODE -ne 0) { throw "First LaTeX pass failed" }
  pdflatex -interaction=nonstopmode -halt-on-error main.tex
  if ($LASTEXITCODE -ne 0) { throw "Second LaTeX pass failed" }
}
finally {
  Pop-Location
}

Copy-Item report/main.pdf report/Bayesian_Market_Making_Report.pdf -Force

Write-Host ""
Write-Host "Reproduction complete."
Write-Host "CSV files: results/data"
Write-Host "Figures:   results/figures"
Write-Host "Paper:     report/Bayesian_Market_Making_Report.pdf"
