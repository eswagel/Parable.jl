"""
    TaskSpec

Executable task plus declarative access metadata.

# Fields
- `name::String`: Human-readable task label.
- `accesses::Vector{Access}`: Access declarations used for dependency analysis.
- `thunk::Function`: Zero-argument function containing task work.
"""
struct TaskSpec
    name::String
    accesses::Vector{Access}
    thunk::Function
end

"""
    TaskSpec(name::String, thunk::Function) -> TaskSpec

Construct a task with an empty access list.
"""
TaskSpec(name::String, thunk::Function) = TaskSpec(name, Access[], thunk)

"""
    add_access!(task::TaskSpec, obj, eff::Effect, reg::Region) -> TaskSpec

Append one access declaration to `task` and return the same task.
"""
function add_access!(task::TaskSpec, obj, eff::Effect, reg::Region)
    push!(task.accesses, access(obj, eff, reg))
    task
end
