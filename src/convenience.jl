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
