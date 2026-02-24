"""
Diagnostics helpers for inspecting accesses, tasks, and DAG structure.
"""

_eff_label(eff::Effect) = string(nameof(typeof(eff)))
_eff_label(eff::Reduce) = "Reduce(" * repr(reduce_op(eff)) * ")"

_region_label(::Whole) = "Whole()"
_region_label(r::Key) = "Key(" * repr(r.k) * ")"
_region_label(r::Block) = "Block(" * repr(r.r) * ")"
_region_label(r::Tile) = "Tile(" * repr(r.I) * ", " * repr(r.J) * ")"
_region_label(r::IndexSet) = "IndexSet(" * repr(r.idxs) * ")"
_region_label(r::Region) = repr(r)

_obj_label(a::Access) = string(summary(a.obj), "#", a.objid)

"""
    show(io::IO, a::Access)

Render an `Access` as a compact single-line summary:

`Effect object#id region`
"""
function Base.show(io::IO, a::Access)
    print(io, _eff_label(a.eff), " ", _obj_label(a), " ", _region_label(a.reg))
end

"""
    show(io::IO, t::TaskSpec)

Render a `TaskSpec` with name and condensed access list.
"""
function Base.show(io::IO, t::TaskSpec)
    print(io, "TaskSpec(", repr(t.name), ", accesses=")
    if isempty(t.accesses)
        print(io, "[]")
    else
        print(io, "[")
        for (i, a) in enumerate(t.accesses)
            i > 1 && print(io, ", ")
            print(io, _eff_label(a.eff), " ", _region_label(a.reg), " @ ", _obj_label(a))
        end
        print(io, "]")
    end
    print(io, ")")
end

"""
    explain_conflict(
        ti::TaskSpec,
        tj::TaskSpec;
        can_parallel_reduce::Bool=false,
    ) -> Union{Nothing, Tuple{Access,Access}}

Return the first conflicting access pair between `ti` and `tj`, or `nothing`
when no conflict is found.
"""
function explain_conflict(ti::TaskSpec, tj::TaskSpec; can_parallel_reduce::Bool=false)
    for ai in ti.accesses
        for aj in tj.accesses
            if conflicts(ai, aj; can_parallel_reduce=can_parallel_reduce)
                return ai, aj
            end
        end
    end
    return nothing
end

"""
    print_dag(dag::DAG; io::IO=stdout)

Print adjacency and levelized structure for a finalized DAG.

# Notes
- If `dag` is not finalized, prints a message and returns.
- Also warns when remaining indegrees suggest a cycle.
"""
function print_dag(dag::DAG; io::IO=stdout)
    n = length(dag.tasks)
    if length(dag.edges) != n || length(dag.indeg) != n
        println(io, "DAG is not finalized; call finalize! first.")
        return
    end

    println(io, "DAG with ", n, " tasks")
    for i in 1:n
        t = dag.tasks[i]
        println(io, "[", i, "] ", t.name, " -> ", dag.edges[i])
    end

    levels, remaining = _dag_levels(dag)
    if any(>(0), remaining)
        println(io, "Warning: DAG may contain cycles; remaining indegrees = ", remaining)
        return
    end

    println(io, "Levels:")
    for (lvl, idxs) in enumerate(levels)
        names = map(i -> dag.tasks[i].name, idxs)
        println(io, "  L", lvl, ": ", idxs, " ", names)
    end
end

function _dag_levels(dag::DAG)
    n = length(dag.tasks)
    indeg = copy(dag.indeg)
    ready = [i for i in 1:n if indeg[i] == 0]
    levels = Vector{Vector{Int}}()

    while !isempty(ready)
        push!(levels, ready)
        next = Int[]
        for i in ready
            for j in dag.edges[i]
                indeg[j] -= 1
                if indeg[j] == 0
                    push!(next, j)
                end
            end
        end
        ready = next
    end

    return levels, indeg
end
