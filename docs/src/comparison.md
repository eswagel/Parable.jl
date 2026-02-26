# Comparison

Parables is best when you want explicit, inspectable task dependencies from effect and region annotations.

## Quick fit check

Parables is usually a strong fit when:

- you have shared-memory workloads,
- work is naturally task-graph shaped,
- and you want dependency logic to be explicit in code.

It is usually not the first tool to reach for when:

- a single `Threads.@threads` loop already models the whole workload,
- the workload is primarily distributed across machines,
- or dependency structure is trivial and static.

## Parables vs `Threads.@threads`

`Threads.@threads` is great for regular data-parallel loops.
Parables is a better fit when:

- Work is naturally a graph, not one loop.
- Different tasks touch different objects/regions.
- You want dependency reasoning to stay explicit in code.

## Parables vs manual `Threads.@spawn`

Manual `@spawn` gives full control but dependency management is on you.
Parables adds:

- Declarative read/write/reduce access metadata
- Automatic DAG edge construction from conflicts
- Diagnostics (`print_dag`, `explain_conflict`)

## Parables vs ad-hoc locks/atomics

Locks and atomics can solve contention but usually make intent harder to read.
Parables shifts correctness to task declarations:

- Safer default ordering from conflict analysis
- Optional reduction privatization for `Reduce(op)` patterns

## Parables vs distributed schedulers

For single-process shared-memory workloads, Parables keeps overhead low and APIs simple.
If you need cluster/distributed execution, specialized distributed runtimes are a better match.

## Rule of thumb

Choose Parables when you want:

- Shared-memory parallelism
- Explicit, auditable dependency structure
- A path from serial correctness to threaded execution with minimal code changes
