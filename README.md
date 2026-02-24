# Detangle.jl

[![Build Status](https://github.com/eswagel/Detangle.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/eswagel/Detangle.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Documentation](https://github.com/eswagel/Detangle.jl/actions/workflows/Documentation.yml/badge.svg?branch=main)](https://github.com/eswagel/Detangle.jl/actions/workflows/Documentation.yml?query=branch%3Amain)

Detangle.jl is a Julia runtime for safe parallel execution with explicit data-access semantics.
You annotate task effects (`Read`, `Write`, `ReadWrite`, `Reduce`) over regions (`Whole`, `Block`, `Key`, `Tile`, `IndexSet`), and Detangle builds a dependency DAG that runs serially or on threads.

## Documentation

[Documentation Home](https://eswagel.github.io/Detangle.jl/dev/)

- [Getting Started](https://eswagel.github.io/Detangle.jl/dev/getting_started/)
- [Manual](https://eswagel.github.io/Detangle.jl/dev/manual/overview/)
- [Tutorials](https://eswagel.github.io/Detangle.jl/dev/tutorials/overview/)
- [API Reference](https://eswagel.github.io/Detangle.jl/dev/manual/api_reference/)

## Installation

From General:

```julia
using Pkg
Pkg.add("Detangle")
```

From GitHub (if needed):

```julia
using Pkg
Pkg.add(url="https://github.com/eswagel/Detangle.jl")
```

## Quick Start

```julia
using Detangle

obj = Ref(0)

dag = Detangle.@dag begin
    Detangle.@spawn Detangle.@task "init" begin
        Detangle.@accesses begin
            (obj, Write(), Whole())
        end
        obj[] = 1
    end

    Detangle.@spawn Detangle.@task "bump" begin
        Detangle.@accesses begin
            (obj, ReadWrite(), Whole())
        end
        obj[] += 1
    end

    Detangle.@spawn Detangle.@task "read" begin
        Detangle.@accesses begin
            (obj, Read(), Whole())
        end
        println("value = ", obj[])
    end
end

print_dag(dag)
execute_serial!(dag)   # debug first
execute_threads!(dag)  # then run parallel
```

## Core API

- DAG macros: `@dag`, `@spawn`, `@task`, `@access`, `@accesses`
- Effects: `Read`, `Write`, `ReadWrite`, `Reduce`
- Regions: `Whole`, `Block`, `Key`, `Tile`, `IndexSet`
- Execution: `execute!`, `execute_serial!`, `execute_threads!`, `execute_privatize!`
- Helpers: `eachblock`, `detangle_foreach`, `detangle_map`, `detangle_mapreduce`

## Examples

- `examples/01_basic_dag.jl`
- `examples/02_block_sum.jl`
- `examples/03_molecular_dynamics.jl`
- `examples/04_histogram.jl`

## Contributing

Contributions to Detangle.jl are welcome! To contribute, please submit a pull request or raise an issue.

## License

This project is licensed under the [MIT License](LICENSE).
