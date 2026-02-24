# Getting Started

This page shows the minimum workflow to install Detangle, build a small DAG, and run it.

## Installation

```julia
import Pkg
Pkg.add("Detangle")
```

For local development in this repository:

```julia
import Pkg
Pkg.develop(path=".")
```

## First DAG

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
execute_serial!(dag)
```

Expected output includes `value = 2`.

## Run on threads

```julia
execute_threads!(dag)
```

Set Julia thread count before startup, for example:

```bash
JULIA_NUM_THREADS=8 julia
```

## Next steps

- Read [Manual Overview](manual/overview.md) for concepts and APIs.
- Run end-to-end scripts in `examples/`.
- See [Comparison](comparison.md) for when Detangle is the right fit.
