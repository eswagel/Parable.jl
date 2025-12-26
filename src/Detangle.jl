module Detangle

include("effects.jl")
include("regions.jl")
include("access.jl")
include("task.jl")
include("conflicts.jl")
include("dag.jl")
include("scheduler_threads.jl")

export Read, Write, ReadWrite, Reduce
export Whole, Key, Block, Tile, IndexSet
export Access, TaskSpec, access, objkey, add_access!
export conflicts, task_conflicts
export DAG, finalize!
export execute!, execute_threads!, execute_serial!

# TODO: include and export remaining modules (macros, diagnostics, reduce_priv) as they are implemented.

end
