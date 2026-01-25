module Detangle

include("effects.jl")
include("regions.jl")
include("access.jl")
include("task.jl")
include("conflicts.jl")
include("dag.jl")
include("scheduler_threads.jl")
include("reduce_priv.jl")
include("macros.jl")
include("diagnostics.jl")

export Read, Write, ReadWrite, Reduce
export is_writeish, is_reduce, reduce_op
export Whole, Key, Block, Tile, IndexSet
export overlaps, ranges_overlap
export Access, TaskSpec, access, objkey, add_access!
export conflicts, task_conflicts
export DAG, finalize!
export execute!, execute_threads!, execute_serial!, execute_privatize!
export @task, @access, @spawn, @dag
export explain_conflict, print_dag

end
