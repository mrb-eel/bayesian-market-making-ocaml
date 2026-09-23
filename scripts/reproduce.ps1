$ErrorActionPreference = "Stop"

Write-Host "Building OCaml project..."
opam exec -- dune build @all

Write-Host "Running OCaml tests..."
opam exec -- dune runtest

Write-Host "Checking experiment outputs..."
python analysis/check_outputs.py --input results/data

Write-Host ""
Write-Host "All reproduction checks passed."
