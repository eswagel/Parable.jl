"""
Reduction privatization backend internals.

When enabled, `reduce_add!` updates per-thread buffers and `combine!` folds
those buffers into destination objects after task execution.
"""

mutable struct Reducer
    obj::Any
    reg::Region
    op::Function
    bufs::Vector{Any}  # per-thread buffers
end

"""
    ReducerKey(objid, reg, op)

Internal key identifying a reduction target by object identity, region, and
operator.
"""
ReducerKey(objid, reg, op) = (objid, reg, op)

struct ReduceContext
    reducers::Dict{Tuple{UInt64, Region, Function}, Reducer}
end

# Global reduction context used by reduce_add! to route updates when privatization is on.
const _reduce_ctx = Ref{Union{Nothing, ReduceContext}}(nothing)

"""
    _reduce_identity(op::Function, ::Type{T}) where {T}

Internal helper that returns identity elements for supported operators.
"""
function _reduce_identity(op::Function, ::Type{T}) where {T}
    if op === (+)
        return zero(T)
    elseif op === (*)
        return one(T)
    else
        error("No identity defined for reduction operator $op. Use + or * for now.")
    end
end

"""
    alloc_reducers(dag::DAG; nthreads::Integer=Threads.maxthreadid()) -> ReduceContext

Allocate per-thread reduction buffers for all `Reduce(...)` accesses in `dag`.

# Supported targets
- `AbstractVector` with regions `Whole()` and `Block(...)`.
"""
function alloc_reducers(dag::DAG; nthreads::Integer=Threads.maxthreadid())
    reducers = Dict{Tuple{UInt64, Region, Function}, Reducer}()
    for task in dag.tasks
        for acc in task.accesses
            is_reduce(acc.eff) || continue
            reg = acc.reg
            obj = acc.obj
            obj isa AbstractVector || error("Reduce privatization supports AbstractVector targets only for now.")

            key = ReducerKey(acc.objid, reg, reduce_op(acc.eff))
            if !haskey(reducers, key)
                T = eltype(obj)
                identity = _reduce_identity(reduce_op(acc.eff), T)
                # Use maxthreadid to cover task migrations across thread pools.
                bufs = Vector{Any}(undef, nthreads)
                if reg isa Whole
                    for i in 1:nthreads
                        buf = similar(obj)
                        fill!(buf, identity)
                        bufs[i] = buf
                    end
                elseif reg isa Block
                    r = reg.r
                    for i in 1:nthreads
                        buf = similar(obj, length(r))
                        fill!(buf, identity)
                        bufs[i] = buf
                    end
                else
                    error("Reduce privatization does not yet support region $(typeof(reg)).")
                end
                reducers[key] = Reducer(obj, reg, reduce_op(acc.eff), bufs)
            end
        end
    end
    ReduceContext(reducers)
end

"""
    reduce_add!(
        obj::AbstractVector,
        op::Function,
        reg::Region,
        idx::Int,
        value,
    ) -> AbstractVector

Accumulate `value` into `obj[idx]` using reduction operator `op`.

# Arguments
- `obj`: Destination vector being reduced into.
- `op`: Reduction operator (for example `+`).
- `reg`: Declared reduction region (`Whole()` or `Block(...)`).
- `idx`: Global index in `obj` to update.
- `value`: Contribution to combine at `idx`.

# Behavior
- In normal execution, updates `obj` directly.
- In privatized execution, updates a thread-local reduction buffer.

# Notes
- `reg` and `op` must match a declared `Reduce(op)` access for the task.
"""
function reduce_add!(obj::AbstractVector, op::Function, reg::Region, idx::Int, value)
    ctx = _reduce_ctx[]
    if ctx === nothing
        # Direct update in serialize mode.
        obj[idx] = op(obj[idx], value)
        return obj
    end

    key = ReducerKey(objectid(obj), reg, op)
    reducer = get(ctx.reducers, key, nothing)
    reducer === nothing && error("No reducer allocated for this object/region/op. Did you declare a Reduce access?")

    # Thread id is used as an index into the per-thread buffers.
    tid = Threads.threadid()
    if reg isa Whole
        buf = reducer.bufs[tid]
        buf[idx] = op(buf[idx], value)
    elseif reg isa Block
        r = reg.r
        if idx < first(r) || idx > last(r)
            error("Index $idx is outside Block region $r.")
        end
        buf = reducer.bufs[tid]
        local_idx = idx - first(r) + 1
        buf[local_idx] = op(buf[local_idx], value)
    else
        error("reduce_add! does not yet support region $(typeof(reg)).")
    end
    return obj
end

"""
    combine!(ctx::ReduceContext)

Internal helper that folds thread-local reduction buffers into destination
objects.
"""
function combine!(ctx::ReduceContext)
    for reducer in values(ctx.reducers)
        obj = reducer.obj
        op = reducer.op
        if reducer.reg isa Whole
            for buf in reducer.bufs
                @inbounds for i in eachindex(obj, buf)
                    obj[i] = op(obj[i], buf[i])
                end
            end
        elseif reducer.reg isa Block
            r = reducer.reg.r
            for buf in reducer.bufs
                @inbounds for (k, i) in enumerate(r)
                    obj[i] = op(obj[i], buf[k])
                end
            end
        else
            error("combine! does not yet support region $(typeof(reducer.reg)).")
        end
    end
end

"""
    execute_privatize!(
        dag::DAG;
        backend=:threads,
        nworkers::Integer=Threads.nthreads(),
    ) -> DAG

Execute `dag` with reduction privatization enabled.

# Arguments
- `backend`: `:threads` or `:serial`.
- `nworkers`: Worker count for threaded backend.

# Behavior
- Re-finalizes with `can_parallel_reduce=true`.
- Allocates reducer buffers for declared `Reduce` accesses.
- Executes the DAG.
- Combines per-thread buffers into real reduction targets.
"""
function execute_privatize!(dag::DAG; backend=:threads, nworkers::Integer=Threads.nthreads())
    # Rebuild edges allowing parallel reduces with the same op.
    finalize!(dag; can_parallel_reduce=true)

    # maxthreadid covers all thread ids that tasks might use across pools.
    nthreads = backend === :threads ? Threads.maxthreadid() : 1
    ctx = alloc_reducers(dag; nthreads=nthreads)
    _reduce_ctx[] = ctx
    try
        if backend === :threads
            execute_threads!(dag; nworkers=nworkers)
        elseif backend === :serial
            execute_serial!(dag)
        else
            error("Unsupported backend: $backend")
        end
    finally
        _reduce_ctx[] = nothing
    end

    combine!(ctx)
    return dag
end
