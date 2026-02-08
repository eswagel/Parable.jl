"""
Convenience helpers to reduce boilerplate when building DAGs.
"""

"""
Create contiguous unit ranges that cover `1:n` with the given `block_size`.
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
Convenience overload for arrays.
"""
eachblock(data::AbstractArray, block_size::Integer) = eachblock(length(data), block_size)

"""
Construct a task from a list of access triples `(obj, eff, reg)` and a thunk.
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
Build a DAG by applying `task_builder` to each block.
`task_builder` must return a TaskSpec.
"""
function detangle_foreach(blocks, task_builder::Function; finalize::Bool=true)
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
Do-block friendly signature: `detangle_foreach(blocks) do r, i ... end`.
"""
detangle_foreach(task_builder::Function, blocks; finalize::Bool=true) =
    detangle_foreach(blocks, task_builder; finalize=finalize)

"""
Append tasks produced by `task_builder` directly into an existing DAG.
"""
function detangle_foreach!(dag::DAG, blocks, task_builder::Function)
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
Do-block friendly signature: `detangle_foreach!(dag, blocks) do r, i ... end`.
"""
detangle_foreach!(dag::DAG, task_builder::Function, blocks) =
    detangle_foreach!(dag, blocks, task_builder)

"""
Map `f` over `data` in blocks and write results into `dest`.

`blocks` should be a collection of index ranges. `f` is applied elementwise.
"""
function detangle_map!(dest::AbstractVector, data::AbstractVector, blocks, f::Function;
    finalize::Bool=true,
    name_prefix::String="map")
    length(dest) == length(data) || error("dest and data must be the same length")

    dag = detangle_foreach(blocks; finalize=false) do r, i
        Detangle.@task "$(name_prefix)-$i" begin
            Detangle.@access data Read() Block(r)
            Detangle.@access dest Write() Block(r)
            @inbounds for idx in r
                dest[idx] = f(data[idx])
            end
        end
    end
    finalize && finalize!(dag)
    dag
end

"""
Map `f` over `data` in blocks and return a new output vector plus the DAG.
"""
function detangle_map(data::AbstractVector, blocks, f::Function;
    finalize::Bool=true,
    name_prefix::String="map")
    dest = similar(data)
    dag = detangle_map!(dest, data, blocks, f; finalize=finalize, name_prefix=name_prefix)
    return dag, dest
end

"""
Reduce `data` in blocks using `mapf` to transform inputs and `op` to combine.

Returns `(dag, result)` where `result` is a length-1 vector storing the scalar.
Use `reduce_strategy=:privatize` for parallel reductions.
"""
function detangle_mapreduce(data::AbstractVector, blocks, op::Function, mapf::Function=identity;
    finalize::Bool=true,
    name_prefix::String="mapreduce")
    acc = zeros(eltype(data), 1)
    dag = detangle_foreach(blocks; finalize=false) do r, i
        Detangle.@task "$(name_prefix)-$i" begin
            Detangle.@access data Read() Block(r)
            Detangle.@access acc Reduce(op) Whole()
            @inbounds for idx in r
                Detangle.reduce_add!(acc, op, Whole(), 1, mapf(data[idx]))
            end
        end
    end
    finalize && finalize!(dag)
    return dag, acc
end
