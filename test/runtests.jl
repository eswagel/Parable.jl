using Test

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using Detangle

include("test_effects.jl")
include("test_regions.jl")
include("test_access_task.jl")
include("test_conflicts.jl")
include("test_dag.jl")
include("test_scheduler.jl")
