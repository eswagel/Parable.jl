"""
    Effect

Abstract supertype for task access effects.

Effects describe how a task interacts with a region of an object and are used
to derive dependency edges in the DAG.
"""
abstract type Effect end

"""
    Read() <: Effect
    Write() <: Effect
    ReadWrite() <: Effect

Effect markers used in access declarations.

- `Read()` means the task only reads a region.
- `Write()` means the task overwrites or mutates a region.
- `ReadWrite()` means the task both reads and mutates a region.
"""
struct Read <: Effect end
struct Write <: Effect end
struct ReadWrite <: Effect end

"""
    Reduce(op) <: Effect

Reduction effect carrying the operator `op`.

# Arguments
- `op`: Associative reduction operator, commonly `+` or `*`.

# Notes
- Parallel reduction behavior depends on execution strategy.
- When using privatized reduction execution, task bodies should update through
  `reduce_add!`.
"""
struct Reduce{Op} <: Effect
    op::Op
end

"""
    is_writeish(eff::Effect) -> Bool

Return whether `eff` should be treated as mutating for conflict analysis.

# Returns
- `false` for `Read()`
- `true` for `Write()`, `ReadWrite()`, and `Reduce(...)`
"""
is_writeish(::Read) = false
is_writeish(::Write) = true
is_writeish(::ReadWrite) = true
is_writeish(::Reduce) = true
is_writeish(::Effect) = false

"""
    is_reduce(eff::Effect) -> Bool

Predicate that returns `true` only for `Reduce(...)` effects.
"""
is_reduce(::Reduce) = true
is_reduce(::Effect) = false

"""
    reduce_op(r::Reduce)

Return the reduction operator stored in `r`.
"""
reduce_op(r::Reduce) = r.op
