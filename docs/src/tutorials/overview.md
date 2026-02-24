# Tutorials Overview

Use the scripts in `examples/` as full tutorials.

During docs build, numbered example scripts (for example `01_basic_dag.jl`) are
automatically converted into tutorial pages and added to the navigation under
this section.

Conversion is configured with `execute=false`, so examples are rendered as
documentation without being run as part of the docs build.

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
