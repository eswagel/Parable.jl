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
    convenience.jl
    diagnostics.jl
  test/
    runtests.jl
    test_conflicts.jl
    test_dag.jl
    test_scheduler.jl
    test_reduce_priv.jl
    test_convenience.jl
  examples/
    01_basic_dag.jl
    02_block_sum.jl
    03_molecular_dynamics.jl
    04_histogram.jl
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
  - Macros: `@task`, `@access`, `@accesses`

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

### `test/test_convenience.jl`
- `eachblock`, `detangle_foreach` basics
- multiple-task returns per block
- `detangle_map` and `detangle_mapreduce`

---

## Examples

### `examples/01_basic_dag.jl`
- 3 tasks with explicit read/write dependencies.

### `examples/02_block_sum.jl`
- Partition `1:N` into blocks.
- Each task reads a block and writes a partial sum (per-block slot).

### `examples/03_molecular_dynamics.jl`
- MD demo with spatial binning and per-block force/integration tasks.
- Saves frames and can build an animation HTML.

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

- `detangle_foreach(blocks; ...)`:
  - Apply a task builder over block ranges.
- `detangle_map(data, blocks, f)`:
  - Elementwise transform into a new output array (returns `dag, dest`).
- `detangle_map!(dest, data, blocks, f)`:
  - Elementwise transform into a provided output array.
- `detangle_mapreduce(data, blocks, op, mapf)`:
  - Parallel reduction using `Reduce(op)` and `reduce_add!` (returns `dag, acc`).

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

---

## Product status (as of February 24, 2026)

This repository has moved from planning to a working MVP implementation.

Implemented and validated:
- Core runtime files listed above are present and wired through `src/Detangle.jl`.
- Test suite passes with `Pkg.test()` (effects, regions, access/task, conflicts, dag, scheduler, macros, diagnostics, reduction privatization, convenience helpers).
- `examples/03_molecular_dynamics.jl` runs end-to-end and writes frames/animation output.
- `examples/04_histogram.jl` validates correctness for both `reduce_strategy=:serialize` and `:privatize`.
- Public API in docs (`@task`, `@access`, `@accesses`, `@dag`, `@spawn`, `execute!`, convenience helpers) is available and exercised.

Current practical value:
- Safe, explicit dependency management for task-parallel scientific kernels.
- Good fit for prototyping and medium-sized workloads where explicit accesses are acceptable.

Primary current limitations:
- Manual access annotations are still required.
- DAG construction is currently pairwise (`O(T^2)`), which will cap scaling on large task counts.
- Region inference/precision is conservative in some paths (by design for safety).

---

## Path forward: automate DAG construction (reduce/manual access burden)

Goal: preserve correctness guarantees while making explicit `@access` optional for common cases.

### Design principle

Do not target a fully automatic static compiler pass first. Use a hybrid model:
- Dynamic tracing for high-confidence automatic inference.
- Macro-assisted inference for simple/indexed patterns.
- Explicit annotations remain the escape hatch for ambiguous/dynamic code.

### Phase 1: Dynamic trace mode (recommended first)

User-facing API:
- Add an inference mode flag to DAG builders/execution:
  - `@dag mode=:explicit begin ... end` (default, current behavior)
  - `@dag mode=:trace begin ... end`
- Or equivalent runtime knob in helper APIs.

How it works:
1) In trace mode, wrap task inputs/objects in lightweight instrumented proxies.
2) Run each task thunk once in record mode (serial, deterministic).
3) Collect observed reads/writes/reduces and touched regions.
4) Materialize `Access` lists onto each `TaskSpec`.
5) Build/finalize DAG using existing conflict rules and execute normally.

Implementation sketch by file:
- `src/task.jl`
  - Add optional field or metadata store for `inferred_accesses` / `access_source` (`:explicit` or `:inferred`).
- `src/access.jl`
  - Add trace record types (`TraceEvent`) and conversion `TraceEvent -> Access`.
- `src/regions.jl`
  - Add helpers to map traced indices/slices to `Region` (`Key`, `Block`, `IndexSet`, `Whole` fallback).
- `src/macros.jl`
  - Extend `@dag` options parsing (`mode`, maybe `trace_strict`).
- `src/dag.jl`
  - Add a pre-finalization trace pass in `mode=:trace`.
- `src/scheduler_threads.jl`
  - No core semantic change required; execution stays identical after access inference.
- `src/diagnostics.jl`
  - Show whether each access was explicit or inferred.

Safety defaults:
- If tracing cannot classify an access precisely, fall back conservatively:
  - effect: `ReadWrite()`
  - region: `Whole()`
- Provide strict mode (`trace_strict=true`) to error instead of falling back.

### Phase 2: Macro-assisted local inference

Scope:
- Infer accesses from obvious forms inside `@task` bodies:
  - `A[i]`, `A[r]`, `A[I, J]`, `A[i] = ...`, `A .+= ...` (limited, conservative).
- Emit inferred `@access` entries at macro expansion time when confidence is high.

Behavior:
- Merge inferred accesses with explicit ones.
- Explicit annotation always wins on conflicts/duplicates.
- Warn when inference is skipped due to ambiguity.

### Phase 3: Incremental/indexed DAG builder

Once access volume increases (from automation), replace all-pairs conflict checks:
- Maintain per-object region/effect index.
- For each new task, only check likely conflicting predecessors.
- Preserve spawn-order tie-breaking and current semantics.

### Testing plan for automation

Add:
- `test/test_trace_inference.jl`
  - compare inferred-access DAG to explicit-access DAG on canonical kernels.
  - ensure conservative fallback preserves correctness.
- `test/test_trace_strict.jl`
  - ambiguous operations fail in strict mode.
- Expand `test/test_macros.jl`
  - macro-assisted inference cases and explicit-override behavior.
- Add example:
  - `examples/05_trace_mode.jl` showing explicit vs trace-mode ergonomics and equivalent results.

### Acceptance criteria for “Auto-DAG v1”

1) Users can omit `@access` in common array/block workflows by using trace mode.
2) Inferred DAG yields the same output as explicit annotations on benchmark examples.
3) Ambiguous code is handled safely (conservative fallback) or rejected in strict mode.
4) Diagnostics clearly report inferred vs explicit dependency metadata.
