# Getting Started

This page covers the minimum path to install Detangle, build a small DAG, and run it safely.

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

## Then Run On Threads

```julia
execute_threads!(dag)
```

Set Julia thread count before startup, for example:

```bash
JULIA_NUM_THREADS=8 julia
```

## Common first checks

- If behavior is unexpected, run `execute_serial!` first.
- Use `print_dag(dag)` to inspect inferred dependencies.
- Verify `@access`/`@accesses` declarations match what task code actually touches.

## Next Steps

- Read [Manual Overview](manual/overview.md) for concepts and APIs.
- Run end-to-end scripts in `examples/` via [Tutorials](tutorials/overview.md).
- See [Comparison](comparison.md) for when Detangle is the right fit.
