"""
Convenience helpers for block-based DAG construction.
"""

"""
    eachblock(n::Integer, block_size::Integer) -> Vector{UnitRange{Int}}

Split `1:n` into contiguous blocks of size `block_size` (last block may be
shorter).

# Arguments
- `n`: Number of logical elements.
- `block_size`: Positive block size.
"""
function eachblock(n::Integer, block_size::Integer)
    n <= 0 && return UnitRange{Int}[]
    block_size <= 0 && error("block_size must be positive")
    blocks = UnitRange{Int}[]
    i = 1
    while i <= n
        push!(blocks, i:min(i + block_size - 1, n))
        i += block_size
    end
    blocks
end

"""
    eachblock(data::AbstractArray, block_size::Integer) -> Vector{UnitRange{Int}}

Convenience overload equivalent to `eachblock(length(data), block_size)`.
"""
eachblock(data::AbstractArray, block_size::Integer) = eachblock(length(data), block_size)

"""
    task_from_accesses(
        name::String,
        accesses::AbstractVector,
        thunk::Function,
    ) -> TaskSpec

Build a `TaskSpec` from a list of access tuples and a zero-arg thunk.

# Arguments
- `name`: Task name.
- `accesses`: Iterable of `(obj, eff, reg)` tuples.
- `thunk`: Task body.
"""
function task_from_accesses(name::String, accesses::AbstractVector, thunk::Function)
    t = TaskSpec(name, thunk)
    for acc in accesses
        acc isa Tuple && length(acc) == 3 || error("access entries must be (obj, eff, reg)")
        obj, eff, reg = acc
        add_access!(t, obj, eff, reg)
    end
    t
end

"""
    parable_foreach(blocks, task_builder::Function; finalize::Bool=true) -> DAG

Build a DAG by applying `task_builder(r, i)` to each block.

# Arguments
- `blocks`: Block collection (commonly ranges from `eachblock`).
- `task_builder`: Function returning a `TaskSpec` or collection of `TaskSpec`.
- `finalize`: If `true`, calls `finalize!` before returning.
"""
function parable_foreach(blocks, task_builder::Function; finalize::Bool=true)
    dag = DAG()
    for (i, r) in enumerate(blocks)
        t = task_builder(r, i)
        if t isa TaskSpec
            push!(dag, t)
        elseif t isa AbstractVector || t isa Tuple
            for ti in t
                ti isa TaskSpec || error("task_builder must return TaskSpec or collection of TaskSpec")
                push!(dag, ti)
            end
        else
            error("task_builder must return TaskSpec or collection of TaskSpec")
        end
    end
    finalize && finalize!(dag)
    dag
end

"""
    parable_foreach(task_builder::Function, blocks; finalize::Bool=true) -> DAG

Do-block friendly overload:

```julia
parable_foreach(blocks) do r, i
    ...
end
```
"""
parable_foreach(task_builder::Function, blocks; finalize::Bool=true) =
    parable_foreach(blocks, task_builder; finalize=finalize)

"""
    parable_foreach!(dag::DAG, blocks, task_builder::Function) -> DAG

Append tasks produced by `task_builder(r, i)` directly to an existing DAG.
"""
function parable_foreach!(dag::DAG, blocks, task_builder::Function)
    for (i, r) in enumerate(blocks)
        t = task_builder(r, i)
        if t isa TaskSpec
            push!(dag, t)
        elseif t isa AbstractVector || t isa Tuple
            for ti in t
                ti isa TaskSpec || error("task_builder must return TaskSpec or collection of TaskSpec")
                push!(dag, ti)
            end
        else
            error("task_builder must return TaskSpec or collection of TaskSpec")
        end
    end
    dag
end

"""
    parable_foreach!(dag::DAG, task_builder::Function, blocks) -> DAG

Do-block friendly overload for `parable_foreach!`.
"""
parable_foreach!(dag::DAG, task_builder::Function, blocks) =
    parable_foreach!(dag, blocks, task_builder)

"""
    parable_map!(
        dest::AbstractVector,
        data::AbstractVector,
        blocks,
        f::Function;
        finalize::Bool=true,
        name_prefix::String="map",
    ) -> DAG

Create block tasks that apply `f` elementwise to `data` and write into `dest`.

# Arguments
- `dest`, `data`: Equal-length vectors.
- `blocks`: Index ranges defining task partitions.
- `f`: Elementwise transform.
- `finalize`: Whether to finalize the returned DAG.
- `name_prefix`: Task name prefix.
"""
function parable_map!(dest::AbstractVector, data::AbstractVector, blocks, f::Function;
    finalize::Bool=true,
    name_prefix::String="map")
    length(dest) == length(data) || error("dest and data must be the same length")

    dag = parable_foreach(blocks; finalize=false) do r, i
        Parable.@task "$(name_prefix)-$i" begin
            Parable.@access data Read() Block(r)
            Parable.@access dest Write() Block(r)
            @inbounds for idx in r
                dest[idx] = f(data[idx])
            end
        end
    end
    finalize && finalize!(dag)
    dag
end

"""
    parable_map(
        data::AbstractVector,
        blocks,
        f::Function;
        finalize::Bool=true,
        name_prefix::String="map",
    ) -> Tuple{DAG, AbstractVector}

Allocate an output vector, build a block map DAG, and return `(dag, dest)`.
"""
function parable_map(data::AbstractVector, blocks, f::Function;
    finalize::Bool=true,
    name_prefix::String="map")
    dest = similar(data)
    dag = parable_map!(dest, data, blocks, f; finalize=finalize, name_prefix=name_prefix)
    return dag, dest
end

"""
    parable_mapreduce(
        data::AbstractVector,
        blocks,
        op::Function,
        mapf::Function=identity;
        finalize::Bool=true,
        name_prefix::String="mapreduce",
    ) -> Tuple{DAG, Vector}

Build a block map-reduce DAG over `data`.

# Arguments
- `data`: Input vector.
- `blocks`: Index ranges for per-task work.
- `op`: Reduction operator used by `Reduce(op)` and `reduce_add!`.
- `mapf`: Per-element transform before reduction.
- `finalize`: Whether to finalize the returned DAG.
- `name_prefix`: Task name prefix.

# Returns
- `(dag, acc)` where `acc` is a length-1 vector storing the reduced value.
"""
function parable_mapreduce(data::AbstractVector, blocks, op::Function, mapf::Function=identity;
    finalize::Bool=true,
    name_prefix::String="mapreduce")
    acc = zeros(eltype(data), 1)
    dag = parable_foreach(blocks; finalize=false) do r, i
        Parable.@task "$(name_prefix)-$i" begin
            Parable.@access data Read() Block(r)
            Parable.@access acc Reduce(op) Whole()
            @inbounds for idx in r
                Parable.reduce_add!(acc, op, Whole(), 1, mapf(data[idx]))
            end
        end
    end
    finalize && finalize!(dag)
    return dag, acc
end
