"""
    conflicts(a::Access, b::Access; can_parallel_reduce::Bool=false) -> Bool

Return whether two accesses require an ordering dependency.

# Arguments
- `a`, `b`: Access declarations to compare.
- `can_parallel_reduce`: If `true`, allows `Reduce(op)` pairs with identical
  `op` to proceed in parallel.

# Rules
- Different objects never conflict.
- Non-overlapping regions never conflict.
- Any write-like effect conflicts, except optional compatible reductions.
"""
function conflicts(a::Access, b::Access; can_parallel_reduce::Bool=false)
    a.objid == b.objid || return false
    overlaps(a.reg, b.reg) || return false

    # If both are reductions, optionally allow parallelism when ops match.
    if can_parallel_reduce && is_reduce(a.eff) && is_reduce(b.eff)
        return reduce_op(a.eff) != reduce_op(b.eff)
    end

    is_writeish(a.eff) || is_writeish(b.eff) || return false
    return true
end

"""
    task_conflicts(ti::TaskSpec, tj::TaskSpec; can_parallel_reduce::Bool=false) -> Bool

Return `true` if any access pair across `ti` and `tj` conflicts.
"""
function task_conflicts(ti::TaskSpec, tj::TaskSpec; can_parallel_reduce::Bool=false)
    any(conflicts(ai, aj; can_parallel_reduce=can_parallel_reduce) for ai in ti.accesses for aj in tj.accesses)
end
