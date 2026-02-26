using Test

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using Parables

include("test_effects.jl")
include("test_regions.jl")
include("test_access_task.jl")
include("test_conflicts.jl")
include("test_dag.jl")
include("test_scheduler.jl")
include("test_macros.jl")
include("test_diagnostics.jl")
include("test_reduce_priv.jl")
include("test_convenience.jl")
