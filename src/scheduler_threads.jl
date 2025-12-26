"""
Execute a finalized DAG. Dispatch to `execute_threads!` or `execute_serial!` based on backend.
"""
function execute!(dag::DAG; backend=:threads, nworkers::Integer=Threads.nthreads())
    if backend === :threads
        return execute_threads!(dag; nworkers=nworkers)
    elseif backend === :serial
        return execute_serial!(dag)
    else
        error("Unsupported backend: $backend")
    end
end

"""
Threaded executor using Julia `Threads.@spawn`.
"""
function execute_threads!(dag::DAG; nworkers::Integer=Threads.nthreads())
    n = length(dag.tasks)
    n == 0 && return dag

    indeg = copy(dag.indeg)
    ready = Channel{Int}(n)
    done = Channel{Int}(n)
    remaining = Threads.Atomic{Int}(n)

    # seed ready queue
    for i in 1:n
        indeg[i] == 0 && put!(ready, i)
    end

    # worker loop
    workers = [Threads.@spawn begin
        for idx in ready
            dag.tasks[idx].thunk()
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
    dag
end

"""
Serial executor useful for debugging dependency construction.
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
