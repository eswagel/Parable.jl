# Parable.jl

[![Build Status](https://github.com/eswagel/Parable.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/eswagel/Parable.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Documentation](https://github.com/eswagel/Parable.jl/actions/workflows/Documentation.yml/badge.svg?branch=main)](https://github.com/eswagel/Parable.jl/actions/workflows/Documentation.yml?query=branch%3Amain)

Parable.jl is a Julia runtime for safe parallel execution with explicit data-access semantics.
You annotate task effects (`Read`, `Write`, `ReadWrite`, `Reduce`) over regions (`Whole`, `Block`, `Key`, `Tile`, `IndexSet`), and Parable builds a dependency DAG that runs serially or on threads.

## Documentation

[Documentation Home](https://eswagel.github.io/Parable.jl/dev/)

- [Getting Started](https://eswagel.github.io/Parable.jl/dev/getting_started/)
- [Manual](https://eswagel.github.io/Parable.jl/dev/manual/overview/)
- [Tutorials](https://eswagel.github.io/Parable.jl/dev/tutorials/overview/)
- [API Reference](https://eswagel.github.io/Parable.jl/dev/manual/api_reference/)

## Installation

From General:

```julia
using Pkg
Pkg.add("Parable")
```

From GitHub (if needed):

```julia
using Pkg
Pkg.add(url="https://github.com/eswagel/Parable.jl")
```

## Quick Start

```julia
using Parable

obj = Ref(0)

dag = Parable.@dag begin
    Parable.@spawn Parable.@task "init" begin
        Parable.@accesses begin
            (obj, Write(), Whole())
        end
        obj[] = 1
    end

    Parable.@spawn Parable.@task "bump" begin
        Parable.@accesses begin
            (obj, ReadWrite(), Whole())
        end
        obj[] += 1
    end

    Parable.@spawn Parable.@task "read" begin
        Parable.@accesses begin
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
- Helpers: `eachblock`, `parable_foreach`, `parable_map`, `parable_mapreduce`

## Examples

- `examples/01_basic_dag.jl`
- `examples/02_block_sum.jl`
- `examples/03_molecular_dynamics.jl`
- `examples/04_histogram.jl`

## Contributing

Contributions to Parable.jl are welcome! To contribute, please submit a pull request or raise an issue.

## License

This project is licensed under the [MIT License](LICENSE).
