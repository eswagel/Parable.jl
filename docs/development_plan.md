# MVP Plan: Effects + Regions Task Runtime (Julia)

Goal: a small package that lets users declare **effects** (read/write/reduce) over explicit **regions**, then automatically builds a dependency DAG and schedules tasks on Julia threads.

This is **not** a full compiler auto-parallelizer. It’s a runtime + lightweight annotation layer that makes safe parallel execution easy for scientific kernels.

---

## Repository layout

```
Detangle.jl/
  Project.toml
  src/
    Detangle.jl
    effects.jl
    regions.jl
    access.jl
    task.jl
    dag.jl
    conflicts.jl
    scheduler_threads.jl
    reduce_priv.jl
    macros.jl
    diagnostics.jl
  test/
    runtests.jl
    test_conflicts.jl
    test_dag.jl
    test_scheduler.jl
    test_reduce_priv.jl
  examples/
    01_basic_dag.jl
    02_blocked_array_mapreduce.jl
    03_particles_cellpairs.jl
```

---

## `src/Detangle.jl`

Package entrypoint.

- `module Detangle`
- `include(...)` all source files
- Export a small, stable public API:
  - Effects: `Read`, `Write`, `ReadWrite`, `Reduce`
  - Regions: `Whole`, `Key`, `Block`, `Tile`, `IndexSet`
  - Task/DAG: `TaskSpec`, `Access`, `DAG`, `@dag`, `@spawn`, `execute!`
  - Macros: `@task`, `@access`

---

## `src/effects.jl`

Defines effect types and helpers.

- `abstract type Effect end`
- `struct Read <: Effect end`, `Write`, `ReadWrite`
- `struct Reduce{Op} <: Effect; op::Op; end`
- Predicates:
  - `is_writeish(::Effect)`
  - `is_reduce(::Effect)`
  - `reduce_op(::Reduce)`

Notes:
- MVP assumes reduction ops are associative/commutative; user responsibility.

---

## `src/regions.jl`

Region types + overlap checks.

- `abstract type Region end`
- `struct Whole <: Region end`
- `struct Key{K} <: Region; k::K end`
- `struct Block <: Region; r::UnitRange{Int} end`
- `struct Tile <: Region; I::UnitRange{Int}; J::UnitRange{Int} end`
- `struct IndexSet{T<:AbstractVector{Int}} <: Region; idxs::T end`

Overlap API:
- `overlaps(a::Region, b::Region)::Bool`
  - `Whole` overlaps everything
  - `Key` overlaps if keys equal
  - `Block` overlaps by range intersection
  - `Tile` overlaps if both ranges intersect
  - `IndexSet` overlaps conservatively (e.g., sort+two-pointer or `BitSet`); start with conservative `true` unless opted-in.

Extensibility:
- Document that users can implement `overlaps(::MyRegion, ::MyRegion)`.

---

## `src/access.jl`

Access declarations bound to an identity key.

- `struct Access
    objid::UInt64
    obj::Any
    eff::Effect
    reg::Region
  end`

Identity:
- `objid = objectid(obj)`; keep `obj` for debugging.
- Helper constructors:
  - `access(obj, eff, reg)`
  - `objkey(obj)` returns `(objectid(obj), obj)`

---

## `src/task.jl`

Task representation.

- `struct TaskSpec
    name::String
    accesses::Vector{Access}
    thunk::Function   # zero-arg closure
  end`

- Helpers:
  - `TaskSpec(name, thunk)` with empty accesses
  - `add_access!(task, obj, eff, reg)`

---

## `src/conflicts.jl`

Conflict rules between accesses and tasks.

- `conflicts(a::Access, b::Access; can_parallel_reduce::Bool=false)::Bool`
  - Must match `objid`
  - Must overlap regions
  - If either is write-ish => conflict
  - Exception (optional): Reduce-Reduce with same op may be allowed when `can_parallel_reduce=true`

- `task_conflicts(ti::TaskSpec, tj::TaskSpec; ...)` (nested-any over accesses)

MVP defaults:
- `can_parallel_reduce=false` unless using the reduction-privatization backend.

---

## `src/dag.jl`

DAG build + representation.

- `struct DAG
    tasks::Vector{TaskSpec}
    edges::Vector{Vector{Int}}  # i -> successors
    indeg::Vector{Int}
  end`

- Builder API:
  - `DAG()` creates empty
  - `push!(dag, task)` appends and (for MVP) rebuilds edges at the end
  - `finalize!(dag; can_parallel_reduce=false)` builds `edges, indeg`

Edge construction:
- MVP: O(T^2) pairwise checks preserving spawn order.
- Leave a TODO section for future incremental/indexed builder.

---

## `src/scheduler_threads.jl`

Threaded executor for a finalized DAG.

- `execute!(dag::DAG; nworkers=Threads.nthreads())`
  - Topological scheduling with a `ready::Channel{Int}`
  - Worker loop: `take!` task index, run `thunk()`, notify `done::Channel{Int}`
  - Completion loop: decrement indegrees, enqueue newly ready tasks

Implementation notes:
- Use `Threads.@spawn` workers.
- Use atomic counter for remaining tasks.
- Provide a `:serial` backend for debugging.

---

## `src/reduce_priv.jl`

Reduction privatization backend (MVP “phase” version).

Purpose:
- Allow concurrent `Reduce(op)` tasks targeting the same `(obj, region)` without atomics by writing into private buffers and combining afterward.

Minimal MVP approach (coarse):
- Treat each `@dag` as a **phase**.
- If any `Reduce` accesses exist, allocate per-thread private storage per `(obj, region, op)`.
- Wrap task thunks so their `Reduce` targets are redirected to private buffers.
- After all tasks, run combine thunks that fold private buffers into the real object.

Implementation checklist:
- Implement `execute_privatize!` so `reduce_strategy=:privatize` runs.
- Add reducer allocation + combine path for `Block` and `Whole` over arrays.
- Provide a fallback hook for `Key(...)` via a user mapping callback.
- Add tests that verify parallel reductions produce the same result as serial.

What’s in this file:
- `execute!(dag; reduce_strategy=:serialize|:privatize)` dispatch
- `ReducerKey = (objid, Region, op)`
- `alloc_reducers(dag)`
- `wrap_thunk_for_reduction(task, reducers)`
- `combine!(reducers)`

Scope limitation:
- Start with reductions into array-like storage where you can map `Region` -> indices.
- For `Key(cell)` style regions, require a user-provided mapping callback:
  - `region_indices(obj, reg)::AbstractVector{Int}` or `region_view(obj, reg)`.

---

## `src/macros.jl`

Ergonomics layer: `@task`, `@access`, `@dag`, `@spawn`.

### `@task "name" begin ... end`
Expands into:
- `TaskSpec(name, () -> ( ...body... ))`
- Within the block, `@access` pushes access metadata into a hidden task-local vector.

### `@access obj Effect() Region()`
Expands into:
- `push!(task.accesses, Access(objectid(obj), obj, eff, reg))`

### `@accesses begin ... end`
Block form for declaring accesses outside the task body:
- Intended to reduce boilerplate in task definitions.
- Expands into a list of `@access`-style entries appended to the task.

### `@dag begin ... end`
Creates a `DAGBuilder` context:
- collects tasks from `@spawn`
- finalizes into `DAG`

### `@spawn expr`
If `expr` returns a `TaskSpec`, append it to the current builder.

MVP simplification:
- `@spawn @task ...` is the primary form.

---

## `src/diagnostics.jl`

Make the system trustable.

- Pretty printers:
  - `show(::Access)` prints `effect obj region`
  - `show(::TaskSpec)` prints name + access summary
- Debug helpers:
  - `explain_conflict(taskA, taskB)` returns the first conflicting access pair
  - `print_dag(dag)` prints edges/levels
- Optional validation:
  - detect duplicate `Write(Whole())` patterns
  - warn when `IndexSet` overlap checks are conservative

---

## Tests

### `test/test_conflicts.jl`
- All pairs of effects, overlapping/non-overlapping regions.
- `Key`, `Block`, `Whole` semantics.

### `test/test_dag.jl`
- Small DAGs where conflicts force ordering.
- Ensure spawn order is respected.

### `test/test_scheduler.jl`
- Use counters/logs to assert:
  - all tasks execute
  - conflicting tasks never overlap (use `Threads.Atomic` flags or timestamps)

### `test/test_reduce_priv.jl`
- Two tasks reducing into same region run concurrently (if enabled)
- Result matches serial reduction.
- Histogram reductions combine correctly.

---

## Examples

### `examples/01_basic_dag.jl`
- 3 tasks with explicit read/write dependencies.

### `examples/02_blocked_array_mapreduce.jl`
- Partition `1:N` into blocks.
- Spawn block tasks that `Reduce(+)` into a global vector or scalar.

### `examples/03_particles_cellpairs.jl`
- Cell-pair tasks:
  - `x => Read(Whole())`
  - `F => Reduce(+) Key(cellA)` and `Key(cellB)`
- Demonstrate:
  - `reduce_strategy=:serialize` (correct baseline)
  - `reduce_strategy=:privatize` (more parallelism)

### `examples/04_histogram.jl`
- Simple histogramming example to showcase reduction privatization.
- Split input data into blocks; each task reduces into shared bins.
- Demonstrate:
  - `reduce_strategy=:serialize` vs `:privatize`
  - correctness match to a serial histogram

---

## Public API summary (MVP)

- Types:
  - `Read`, `Write`, `ReadWrite`, `Reduce`
  - `Whole`, `Key`, `Block`, `Tile`, `IndexSet`
  - `Access`, `TaskSpec`, `DAG`

- Macros:
  - `@task`, `@access`, `@accesses`, `@dag`, `@spawn`

- Execution:
  - `execute!(dag; backend=:threads, reduce_strategy=:serialize)`

- Extensibility hooks:
  - `overlaps(::Region, ::Region)`
  - `region_indices(obj, reg)` (needed for reduction privatization beyond simple blocks)

## Higher-level APIs (ergonomics phase)

Goal: make common data-parallel use cases concise and reduce boilerplate.

- `detangle_foreach(data, blocks; ...)`:
  - Partition data into blocks and apply a task body.
  - Automatically declares Read/Write/Reduce accesses based on user-supplied access spec.

- `detangle_map(data, blocks; ...)`:
  - Like foreach, but writes into an output array or returns a collected result.

- `detangle_mapreduce(data, blocks, op; ...)`:
  - Parallel reduction using Detangle access metadata (backed by privatization).

Convenience building blocks:
- `eachblock(data, block_size)` iterator to produce `Block` regions.
- `@accesses` block for concise access declaration.
- Task builder/pipeline helpers for common loops and DAG creation.

---

## MVP “done” criteria

1) Users can define tasks with accesses and run them in parallel safely.
2) Conflicting writes force ordering; non-conflicting tasks run concurrently.
3) A particle-style demo works with cellpair tasks (even if conservative).
4) Diagnostics can explain why two tasks are ordered.
5) Reduction privatization runs and a simple histogram example demonstrates its value.
6) Higher-level APIs and access blocks reduce boilerplate for common patterns.

That’s enough to validate the concept and decide whether to invest in:
- incremental/indexed dependency building
- better region inference
- distributed/GPU backends
- richer reduction semantics
