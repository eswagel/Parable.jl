"""
Base type for all effects.
"""
abstract type Effect end

"""
Effect tags used to derive dependency rules for tasks.
"""
struct Read <: Effect end
struct Write <: Effect end
struct ReadWrite <: Effect end

"""
Reduction effect carrying a user-supplied associative/commutative operator.
"""
struct Reduce{Op} <: Effect
    op::Op
end

"""
Treat anything that mutates (including reductions) as write-ish for conflict checks.
"""
is_writeish(::Read) = false
is_writeish(::Write) = true
is_writeish(::ReadWrite) = true
is_writeish(::Reduce) = true
is_writeish(::Effect) = false

"""
Reducer convenience predicates/helpers.
"""
is_reduce(::Reduce) = true
is_reduce(::Effect) = false

"""
Return the underlying reduction operator.
"""
reduce_op(r::Reduce) = r.op
