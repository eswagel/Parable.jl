"""
Macro to declare a task with a name and body. `@access` statements record
metadata; remaining statements form the task thunk.
"""
macro task(name, block)
    accesses_sym = gensym(:accesses)

    # Build an expression that executes only @access calls (preserving control flow).
    function collect_accesses(ex)
        if ex isa LineNumberNode
            return ex
        elseif ex isa Expr
            if ex.head == :macrocall
                macroref = ex.args[1]
                is_access = macroref == Symbol("@access")
                if macroref isa Expr && macroref.head == :.
                    lastarg = macroref.args[end]
                    is_access |= lastarg == Symbol("@access") || (lastarg isa QuoteNode && lastarg.value == Symbol("@access"))
                elseif macroref isa GlobalRef
                    is_access |= macroref.name == Symbol("@access")
                end
                if is_access
                    length(ex.args) >= 4 || error("@access requires obj, eff, reg")
                    obj = ex.args[end-2]
                    eff = ex.args[end-1]
                    reg = ex.args[end]
                    # Replace @access call with a push into the task-local access list.
                    return :(push!($(accesses_sym), access($(obj), $(eff), $(reg))))
                end
            end
            if ex.head == :block
                return Expr(:block, filter(!isnothing, map(collect_accesses, ex.args))...)
            elseif ex.head == :for || ex.head == :while
                return Expr(ex.head, ex.args[1], collect_accesses(ex.args[2]))
            elseif ex.head == :if
                return Expr(:if, ex.args[1], collect_accesses(ex.args[2]), collect_accesses(ex.args[3]))
            elseif ex.head == :let
                return Expr(:let, ex.args[1:end-1]..., collect_accesses(ex.args[end]))
            else
                return nothing
            end
        else
            return nothing
        end
    end

    # Remove @access calls from the task body (so they don't run at execution time).
    function strip_accesses(ex)
        if ex isa LineNumberNode
            return ex
        elseif ex isa Expr
            if ex.head == :macrocall
                macroref = ex.args[1]
                is_access = macroref == Symbol("@access")
                if macroref isa Expr && macroref.head == :.
                    lastarg = macroref.args[end]
                    is_access |= lastarg == Symbol("@access") || (lastarg isa QuoteNode && lastarg.value == Symbol("@access"))
                elseif macroref isa GlobalRef
                    is_access |= macroref.name == Symbol("@access")
                end
                is_access && return nothing
            end
            return Expr(ex.head, filter(!isnothing, map(strip_accesses, ex.args))...)
        else
            return ex
        end
    end

    access_body = collect_accesses(block)
    body = strip_accesses(block)
    return esc(quote
        local $(accesses_sym) = Access[]
        $(access_body)
        TaskSpec($(name), $(accesses_sym), () -> begin
            $(body)
        end)
    end)
end

"""
Macro to record an access inside a `@task` body.
"""
macro access(obj, eff, reg)
    error("@access is only valid inside @task")
end

"""
Macro to append a task into the current DAG builder.
"""
macro spawn(expr)
    return esc(:(push!(__detangle_builder, $(expr))))
end

"""
Macro to build and finalize a DAG from spawned tasks.
"""
macro dag(block)
    builder = gensym(:builder)
    return quote
        local $(builder) = DAG()
        let $(esc(:__detangle_builder)) = $(builder)
            $(esc(block))
        end
        finalize!($(builder))
    end
end
