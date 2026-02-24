# Comparison

Detangle is best when you want explicit, inspectable task dependencies from effect and region annotations.

## Detangle vs `Threads.@threads`

`Threads.@threads` is great for regular data-parallel loops.
Detangle is a better fit when:

- Work is naturally a graph, not one loop.
- Different tasks touch different objects/regions.
- You want dependency reasoning to stay explicit in code.

## Detangle vs manual `Threads.@spawn`

Manual `@spawn` gives full control but dependency management is on you.
Detangle adds:

- Declarative read/write/reduce access metadata
- Automatic DAG edge construction from conflicts
- Diagnostics (`print_dag`, `explain_conflict`)

## Detangle vs ad-hoc locks/atomics

Locks and atomics can solve contention but usually make intent harder to read.
Detangle shifts correctness to task declarations:

- Safer default ordering from conflict analysis
- Optional reduction privatization for `Reduce(op)` patterns

## Detangle vs distributed schedulers

For single-process shared-memory workloads, Detangle keeps overhead low and APIs simple.
If you need cluster/distributed execution, specialized distributed runtimes are a better match.

## Rule of thumb

Choose Detangle when you want:

- Shared-memory parallelism
- Explicit, auditable dependency structure
- A path from serial correctness to threaded execution with minimal code changes
