# Parables.jl

[![Build Status](https://github.com/eswagel/Parables.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/eswagel/Parables.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Documentation](https://github.com/eswagel/Parables.jl/actions/workflows/Documentation.yml/badge.svg?branch=main)](https://github.com/eswagel/Parables.jl/actions/workflows/Documentation.yml?query=branch%3Amain)

Parables.jl is a Julia runtime for safe parallel execution with explicit data-access semantics.
You annotate task effects (`Read`, `Write`, `ReadWrite`, `Reduce`) over regions (`Whole`, `Block`, `Key`, `Tile`, `IndexSet`), and Parables builds a dependency DAG that runs serially or on threads.

## Documentation

[Documentation Home](https://eswagel.github.io/Parables.jl/dev/)

- [Getting Started](https://eswagel.github.io/Parables.jl/dev/getting_started/)
- [Manual](https://eswagel.github.io/Parables.jl/dev/manual/overview/)
- [Tutorials](https://eswagel.github.io/Parables.jl/dev/tutorials/overview/)
- [API Reference](https://eswagel.github.io/Parables.jl/dev/manual/api_reference/)

## Installation

From General:

```julia
using Pkg
Pkg.add("Parables")
```

From GitHub (if needed):

```julia
using Pkg
Pkg.add(url="https://github.com/eswagel/Parables.jl")
```

## Quick Start

```julia
using Parables

obj = Ref(0)

dag = Parables.@dag begin
    Parables.@spawn Parables.@task "init" begin
        Parables.@accesses begin
            (obj, Write(), Whole())
        end
        obj[] = 1
    end

    Parables.@spawn Parables.@task "bump" begin
        Parables.@accesses begin
            (obj, ReadWrite(), Whole())
        end
        obj[] += 1
    end

    Parables.@spawn Parables.@task "read" begin
        Parables.@accesses begin
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
- Helpers: `eachblock`, `parables_foreach`, `parables_map`, `parables_mapreduce`

## Examples

- `examples/01_basic_dag.jl`
- `examples/02_block_sum.jl`
- `examples/03_molecular_dynamics.jl`
- `examples/04_histogram.jl`

## Contributing

Contributions to Parables.jl are welcome! To contribute, please submit a pull request or raise an issue.

## License

This project is licensed under the [MIT License](LICENSE).
