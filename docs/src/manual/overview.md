# Manual Overview

This manual is split into three layers:

- **Overview (this page):** mental model plus one runnable example.
- **Concepts and Semantics:** detailed rules for effects, regions, and conflict detection.
- **API Reference:** generated docs for all exported types, functions, and macros.

If you are new to Detangle, start here, run the example, then continue to the Concepts page.

## The mental model

Detangle separates:

- **Task code**: the computation you want to run.
- **Access metadata**: what each task reads/writes/reduces.

From that metadata, Detangle builds a dependency DAG and executes it safely (serially or on threads).

## A complete example

```julia
using Detangle

x = rand(100)
y = similar(x)
blocks = eachblock(length(x), 25)

dag = Detangle.@dag begin
    for (i, r) in enumerate(blocks)
        Detangle.@spawn Detangle.@task "scale-$i" begin
            Detangle.@access x Read() Block(r)
            Detangle.@access y Write() Block(r)
            @inbounds for idx in r
                y[idx] = 2 * x[idx]
            end
        end
    end
end

# Optional: inspect the inferred dependency structure.
print_dag(dag)

# Run serially first for correctness/debuggability.
execute_serial!(dag)

# Then run threaded for parallel execution.
execute_threads!(dag)
```

Why these tasks can run in parallel:

- Every task only reads from `x`.
- Every task writes to a non-overlapping `Block(r)` of `y`.

## Where to go next

- [Concepts and Semantics](concepts.md)
- [API Reference](api_reference.md)
