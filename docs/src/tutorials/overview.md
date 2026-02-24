# Tutorials Overview

Tutorial pages are generated from numbered scripts in `examples/` (for example, `01_basic_dag.jl`) and added to the docs navigation automatically.

## How tutorial generation works

- Source code is rendered directly from each example script.
- Most tutorials are rendered-only (the script is not executed during docs build).
- Some tutorials include generated output sections:
  - Molecular dynamics: animation generated from existing frame CSVs in `examples/output/`
  - Histogram: real terminal output captured from running `examples/04_histogram.jl`

## 1. Basic DAG construction

File: `examples/01_basic_dag.jl`

What it covers:

- Building a small DAG with `@dag`, `@spawn`, `@task`
- Annotating accesses with `@accesses`
- Running with `execute_serial!` and `execute_threads!`

Run:

```bash
julia --project=. examples/01_basic_dag.jl
```

## 2. Blocked map/reduce-style workload

File: `examples/02_block_sum.jl`

What it covers:

- Splitting work via `eachblock`
- Creating one task per block with `detangle_foreach`
- Comparing threaded DAG execution to a serial baseline

Run:

```bash
JULIA_NUM_THREADS=8 julia --project=. examples/02_block_sum.jl
```

## 3. Molecular dynamics style pipeline

File: `examples/03_molecular_dynamics.jl`

What it covers:

- Multi-stage per-block pipelines
- Whole-array reads plus block-local writes
- Reusing a DAG across many simulation steps

Run:

```bash
JULIA_NUM_THREADS=8 julia --project=. examples/03_molecular_dynamics.jl
```

## 4. Parallel histogram with reduction privatization

File: `examples/04_histogram.jl`

What it covers:

- `Reduce(+)` access declarations
- `reduce_add!` for reduction updates
- `execute!(...; reduce_strategy=:privatize)`

Run:

```bash
JULIA_NUM_THREADS=8 julia --project=. examples/04_histogram.jl
```
