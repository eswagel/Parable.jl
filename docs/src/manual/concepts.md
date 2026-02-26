# Concepts and Semantics

This page defines the core entities and rules Parables uses to infer safe execution order.

## Core entities

- `TaskSpec`: one task's name, access list, and computation thunk.
- `Access`: one declaration of `(object, effect, region)`.
- `DAG`: all tasks plus inferred dependency edges.

A useful way to read this is:

- `TaskSpec` says *what to run*.
- `Access` says *what that task touches*.
- `DAG` says *what must happen before what*.

## Access declaration pattern

In task code, accesses are typically declared with:

- `@access obj effect region` for one access
- `@accesses begin ... end` for a batch of access tuples

The declarations should match what the task body actually touches.

## Effects

Effects describe **how** a task interacts with data.

- `Read()`: task only reads.
- `Write()`: task mutates/overwrites.
- `ReadWrite()`: task reads and mutates.
- `Reduce(op)`: task contributes to a reduction using operator `op`.

In conflict analysis, write-like effects are the important boundary:

- `Read` is non-mutating.
- `Write`, `ReadWrite`, and `Reduce` are treated as write-like by default.

## Regions

Regions describe **where** an effect applies.

- `Whole()`: entire object.
- `Block(r)`: contiguous 1D range.
- `Tile(I, J)`: 2D rectangular slice.
- `Key(k)`: one keyed partition.
- `IndexSet(idxs)`: sparse explicit indices.

Granularity matters: finer regions expose more parallelism when accesses do not overlap.

## Conflict detection

Two accesses conflict when all three are true:

1. Same object identity.
2. Overlapping region.
3. At least one write-like effect.

If accesses conflict, Parables inserts an ordering edge in the DAG.

## Common pitfalls

- Under-declaring writes as reads: this can hide true dependencies.
- Overly broad regions (for example `Whole()` everywhere): this can serialize work unnecessarily.
- Mismatching declared regions and actual indexing in the task body.
- Assuming `IndexSet` is fully precise: overlap checks are conservative for `IndexSet` pairs.

## Practical examples

### No conflict

- `Read(x, Block(1:50))`
- `Write(x, Block(51:100))`

Same object, but disjoint blocks, so these can run concurrently.

### Conflict

- `Read(x, Block(1:50))`
- `Write(x, Block(25:75))`

Blocks overlap, and one side writes, so ordering is required.

### Key-partitioned updates

- `Write(counts, Key(:A))`
- `Write(counts, Key(:B))`

Different keys do not overlap, so these can run concurrently.

## Reduction note

`Reduce(op)` declares reduction intent. With the privatization strategy, reductions with compatible operators can run in parallel and merge safely afterward.

See [API Reference](api_reference.md) for exact signatures and options.
