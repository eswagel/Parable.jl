"""
Dependency graph over tasks with adjacency lists and indegree counts.
"""
mutable struct DAG
    tasks::Vector{TaskSpec}
    edges::Vector{Vector{Int}}  # i -> successors
    indeg::Vector{Int}
end

"""
Create an empty DAG. Edges/indegrees are filled in by `finalize!`.
"""
DAG() = DAG(TaskSpec[], Vector{Vector{Int}}(), Int[])

"""
Append a task to the DAG. Edges are rebuilt on `finalize!`.
"""
function Base.push!(dag::DAG, task::TaskSpec)
    push!(dag.tasks, task)
    dag
end

"""
Build edges and indegrees based on conflicts, preserving spawn order.
O(T^2) pairwise conflict check for MVP.
"""
function finalize!(dag::DAG; can_parallel_reduce::Bool=false)
    n = length(dag.tasks)
    edges = [Int[] for _ in 1:n]
    indeg = zeros(Int, n)

    for i in 1:n-1
        ti = dag.tasks[i]
        for j in i+1:n
            tj = dag.tasks[j]
            if task_conflicts(ti, tj; can_parallel_reduce=can_parallel_reduce)
                push!(edges[i], j)
                indeg[j] += 1
            end
        end
    end

    dag.edges = edges
    dag.indeg = indeg
    dag
end
