"""
Macro to declare a task with a name and body. `@access` statements record
metadata; remaining statements form the task thunk.
"""
macro task(name, block)
    accesses_sym = gensym(:accesses)
    stmts = (block isa Expr && block.head == :block) ? block.args : Any[block]

    access_pushes = Expr[]
    body_stmts = Expr[]

    for st in stmts
        if st isa LineNumberNode
            continue
        elseif st isa Expr && st.head == :macrocall
            macroref = st.args[1]
            is_access = macroref == Symbol("@access")
            if macroref isa Expr && macroref.head == :.
                lastarg = macroref.args[end]
                is_access |= lastarg == Symbol("@access") || (lastarg isa QuoteNode && lastarg.value == Symbol("@access"))
            elseif macroref isa GlobalRef
                is_access |= macroref.name == Symbol("@access")
            end
            if is_access
                length(st.args) >= 4 || error("@access requires obj, eff, reg")
                obj = st.args[end-2]
                eff = st.args[end-1]
                reg = st.args[end]
                push!(access_pushes, :(push!($(accesses_sym), access($(esc(obj)), $(esc(eff)), $(esc(reg))))))
                continue
            end
        end
        push!(body_stmts, st)
    end

    return quote
        local $(accesses_sym) = Access[]
        $(access_pushes...)
        TaskSpec($(esc(name)), $(accesses_sym), () -> begin
            $(map(esc, body_stmts)...)
        end)
    end
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
