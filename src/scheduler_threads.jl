"""
    execute!(
        dag::DAG;
        backend=:threads,
        nworkers::Integer=Threads.nthreads(),
        reduce_strategy=:serialize,
    ) -> DAG

Execute a finalized DAG with the selected backend and reduction strategy.

# Arguments
- `backend`: `:threads` or `:serial`.
- `nworkers`: Number of worker tasks when `backend=:threads`.
- `reduce_strategy`: `:serialize` (default) or `:privatize`.

# Returns
- The executed `dag`.
"""
function execute!(dag::DAG; backend=:threads, nworkers::Integer=Threads.nthreads(), reduce_strategy=:serialize)
    if reduce_strategy === :serialize
        if backend === :threads
            return execute_threads!(dag; nworkers=nworkers)
        elseif backend === :serial
            return execute_serial!(dag)
        else
            error("Unsupported backend: $backend")
        end
    elseif reduce_strategy === :privatize
        return execute_privatize!(dag; backend=backend, nworkers=nworkers)
    else
        error("Unsupported reduce_strategy: $reduce_strategy")
    end
end

"""
    execute_threads!(dag::DAG; nworkers::Integer=Threads.nthreads()) -> DAG

Execute `dag` using Julia threads with a ready-queue scheduler.

# Arguments
- `nworkers`: Number of worker tasks spawned to process ready nodes.

# Notes
- Assumes `dag` has valid `edges`/`indeg` from `finalize!`.
- Rethrows the first task error after workers complete.
"""
function execute_threads!(dag::DAG; nworkers::Integer=Threads.nthreads())
    n = length(dag.tasks)
    n == 0 && return dag

    indeg = copy(dag.indeg)
    ready = Channel{Int}(n)
    done = Channel{Int}(n)
    errors = Channel{Tuple{Any, Any}}(n)
    remaining = Threads.Atomic{Int}(n)

    # seed ready queue
    for i in 1:n
        indeg[i] == 0 && put!(ready, i)
    end

    # worker loop
    workers = [Threads.@spawn begin
        for idx in ready
            try
                dag.tasks[idx].thunk()
            catch err
                put!(errors, (err, catch_backtrace()))
            end
            put!(done, idx)
            Threads.atomic_sub!(remaining, 1)
        end
    end for _ in 1:nworkers]

    # completion loop: track deps, enqueue newly ready tasks
    while remaining[] > 0
        idx = take!(done)
        for succ in dag.edges[idx]
            indeg[succ] -= 1
            if indeg[succ] == 0
                put!(ready, succ)
            end
        end
    end

    close(ready)
    foreach(wait, workers)
    close(done)
    close(errors)

    if isready(errors)
        err, bt = take!(errors)
        showerror(stderr, err, bt)
        println(stderr)
        throw(err)
    end
    dag
end

"""
    execute_serial!(dag::DAG) -> DAG

Execute `dag` in topological order on the current thread.

Useful for debugging and correctness baselines.
"""
function execute_serial!(dag::DAG)
    n = length(dag.tasks)
    n == 0 && return dag

    indeg = copy(dag.indeg)
    ready = [i for i in 1:n if indeg[i] == 0]

    while !isempty(ready)
        idx = popfirst!(ready)
        dag.tasks[idx].thunk()
        for succ in dag.edges[idx]
            indeg[succ] -= 1
            indeg[succ] == 0 && push!(ready, succ)
        end
    end

    dag
end
