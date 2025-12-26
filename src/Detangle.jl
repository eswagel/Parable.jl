module Detangle

include("effects.jl")
include("regions.jl")
include("access.jl")
include("task.jl")
include("conflicts.jl")

export Read, Write, ReadWrite, Reduce
export Whole, Key, Block, Tile, IndexSet
export Access, TaskSpec, access, objkey, add_access!
export conflicts, task_conflicts

# TODO: include and export remaining modules (conflicts, dag, scheduler, macros, diagnostics, reduce_priv) as they are implemented.

end
