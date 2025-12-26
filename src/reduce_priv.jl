"""
Placeholder for reduction privatization backend.

`execute_privatize!` is intended to run Reduce tasks in parallel by redirecting
writes into per-thread buffers and combining afterward. The MVP leaves this
unimplemented and errors when requested.
"""
function execute_privatize!(dag::DAG; backend=:threads, nworkers::Integer=Threads.nthreads())
    error("reduce_strategy=:privatize not implemented yet for backend=$backend")
end

# Skeletons for future implementation.

"""
Key used to identify a reduction target: object id, region, and operator.
"""
ReducerKey(objid, reg, op) = (objid, reg, op)

alloc_reducers(::DAG) = error("alloc_reducers not implemented")
wrap_thunk_for_reduction(task::TaskSpec, reducers) = error("wrap_thunk_for_reduction not implemented")
combine!(reducers) = error("combine! not implemented")
