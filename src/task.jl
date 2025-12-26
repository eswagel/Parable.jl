"""
Task specification: name, declared accesses, and the zero-arg thunk to run.
"""
struct TaskSpec
    name::String
    accesses::Vector{Access}
    thunk::Function
end

"""
Construct a task with an empty access list.
"""
TaskSpec(name::String, thunk::Function) = TaskSpec(name, Access[], thunk)

"""
Add an access to a task by deriving the object identity.
"""
function add_access!(task::TaskSpec, obj, eff::Effect, reg::Region)
    push!(task.accesses, access(obj, eff, reg))
    task
end
