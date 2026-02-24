# Detangle.jl

Detangle.jl is a Julia runtime for safe parallel execution.
You annotate task effects (`Read`, `Write`, `ReadWrite`, `Reduce`) over explicit regions (`Whole`, `Block`, `Key`, ...), and Detangle builds a dependency DAG that can run serially or on threads.

## Why Detangle

- You write task logic directly in Julia.
- Access annotations make dependencies explicit and debuggable.
- The same DAG can run with different execution backends.

## Quick Links

- [Getting Started](getting_started.md)
- [Manual](manual/overview.md)
- [Tutorials](tutorials/overview.md)
- [Comparison](comparison.md)

## Core API at a glance

- Effects: `Read`, `Write`, `ReadWrite`, `Reduce`
- Regions: `Whole`, `Block`, `Key`, `Tile`, `IndexSet`
- DAG building: `@dag`, `@spawn`, `@task`, `@access`, `@accesses`
- Execution: `execute!`, `execute_threads!`, `execute_serial!`, `execute_privatize!`
- Helpers: `eachblock`, `detangle_foreach`, `detangle_map`, `detangle_mapreduce`
