# Detangle

[![Build Status](https://github.com/eswagel/Detangle.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/eswagel/Detangle.jl/actions/workflows/CI.yml?query=branch%3Amain)

Detangle is a small Julia runtime for safe parallel execution. You declare effects
(read/write/reduce) over explicit regions, Detangle builds a dependency DAG, and
schedules tasks on Julia threads.

## Installation

If Detangle is registered in General:

```
julia> using Pkg
julia> Pkg.add("Detangle")
```

If you are installing before registry publication:

```julia
julia> using Pkg
julia> Pkg.add(url="https://github.com/eswagel/Detangle.jl")
```

## Tiny example

```julia
using Detangle

obj = Ref(0) # Ref gives a stable, mutable container to demonstrate Read/Write on a single value.

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

execute_threads!(dag)
```

## More details

- Documentation home: `docs/` (or `docs/src/index.md`)
- Getting started guide: `docs/src/getting_started.md`
- Manual overview: `docs/src/manual/overview.md`
- Tutorials: `docs/src/tutorials/overview.md`
- Examples: `examples/`
