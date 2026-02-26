# Getting Started

This page covers the minimum path to install Parable, build a small DAG, and run it safely.

## Installation

```julia
import Pkg
Pkg.add("Parable")
```

For local development in this repository:

```julia
import Pkg
Pkg.develop(path=".")
```

## First DAG

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
- See [Comparison](comparison.md) for when Parable is the right fit.
