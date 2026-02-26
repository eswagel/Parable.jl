# Manual Overview

This manual is split into three layers:

- **Overview (this page):** mental model plus one runnable example.
- **Concepts and Semantics:** detailed rules for effects, regions, and conflict detection.
- **API Reference:** generated docs for all exported types, functions, and macros.

If you are new to Parable, start here, run the example, then continue to the Concepts page.

## Who this manual is for

This manual assumes you are comfortable with Julia and want to:

- express task-level parallel work,
- make data dependencies explicit,
- and debug scheduling behavior with predictable rules.

## The mental model

Parable separates:

- **Task code**: the computation you want to run.
- **Access metadata**: what each task reads/writes/reduces.

From that metadata, Parable builds a dependency DAG and executes it safely with
either a serial or threaded backend.

## A complete example

```julia
using Parable

x = rand(100)
y = similar(x)
blocks = eachblock(length(x), 25)

dag = Parable.@dag begin
    for (i, r) in enumerate(blocks)
        Parable.@spawn Parable.@task "scale-$i" begin
            Parable.@access x Read() Block(r)
            Parable.@access y Write() Block(r)
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

If the writes overlapped, Parable would introduce ordering edges automatically.

## Where to go next

- [Concepts and Semantics](concepts.md)
- [API Reference](api_reference.md)
