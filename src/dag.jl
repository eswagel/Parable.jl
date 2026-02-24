"""
    DAG

Dependency graph over `TaskSpec` nodes.

# Fields
- `tasks::Vector{TaskSpec}`: Tasks in insertion order.
- `edges::Vector{Vector{Int}}`: Adjacency list (`i -> successors`).
- `indeg::Vector{Int}`: Indegree count for each task.

# Notes
- A newly created `DAG()` contains tasks only after `push!`.
- Call `finalize!` to construct `edges` and `indeg`.
"""
mutable struct DAG
    tasks::Vector{TaskSpec}
    edges::Vector{Vector{Int}}  # i -> successors
    indeg::Vector{Int}
end

"""
    DAG() -> DAG

Create an empty DAG builder with no tasks and no computed edges.
"""
DAG() = DAG(TaskSpec[], Vector{Vector{Int}}(), Int[])

"""
    push!(dag::DAG, task::TaskSpec) -> DAG

Append `task` to `dag` and return the same DAG.

# Notes
- This does not recompute dependencies. Call `finalize!` after appending tasks.
"""
function Base.push!(dag::DAG, task::TaskSpec)
    push!(dag.tasks, task)
    dag
end

"""
    finalize!(dag::DAG; can_parallel_reduce::Bool=false) -> DAG

Build dependency edges and indegrees for `dag` using pairwise task conflict
checks while preserving insertion order.

# Arguments
- `can_parallel_reduce`: If `true`, compatible `Reduce(op)` tasks may execute
  concurrently.

# Complexity
- `O(T^2)` over number of tasks.
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
