"""
    @task name begin
        ...
    end

Create a `TaskSpec` from a task body.

# Behavior
- Collects `@access obj eff reg` and `@accesses begin ... end` declarations into
  `TaskSpec.accesses`.
- Removes those access declarations from the runtime thunk so they are metadata
  only.
- Stores remaining statements as the task's zero-argument thunk.

# Arguments
- `name`: Task name expression that must evaluate to a `String`.
- `begin ... end`: Task body containing access declarations and work.

# Example
```julia
Parable.@task "scale" begin
    Parable.@access x Read() Whole()
    Parable.@access y Write() Whole()
    y .= 2 .* x
end
```
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
                is_accesses = macroref == Symbol("@accesses")
                if macroref isa Expr && macroref.head == :.
                    lastarg = macroref.args[end]
                    is_access |= lastarg == Symbol("@access") || (lastarg isa QuoteNode && lastarg.value == Symbol("@access"))
                    is_accesses |= lastarg == Symbol("@accesses") || (lastarg isa QuoteNode && lastarg.value == Symbol("@accesses"))
                elseif macroref isa GlobalRef
                    is_access |= macroref.name == Symbol("@access")
                    is_accesses |= macroref.name == Symbol("@accesses")
                end
                if is_access
                    length(ex.args) >= 4 || error("@access requires obj, eff, reg")
                    obj = ex.args[end-2]
                    eff = ex.args[end-1]
                    reg = ex.args[end]
                    # Replace @access call with a push into the task-local access list.
                    return :(push!($(accesses_sym), access($(obj), $(eff), $(reg))))
                elseif is_accesses
                    length(ex.args) >= 2 || error("@accesses requires a block")
                    blk = ex.args[end]
                    blk isa Expr && blk.head == :block || error("@accesses expects a begin...end block")
                    entries = Any[]
                    for ent in blk.args
                        ent isa LineNumberNode && continue
                        if ent isa Expr && ent.head == :tuple && length(ent.args) == 3
                            obj, eff, reg = ent.args
                            push!(entries, :(push!($(accesses_sym), access($(obj), $(eff), $(reg)))))
                        else
                            error("@accesses entries must be (obj, eff, reg) tuples")
                        end
                    end
                    return Expr(:block, entries...)
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
                is_accesses = macroref == Symbol("@accesses")
                if macroref isa Expr && macroref.head == :.
                    lastarg = macroref.args[end]
                    is_access |= lastarg == Symbol("@access") || (lastarg isa QuoteNode && lastarg.value == Symbol("@access"))
                    is_accesses |= lastarg == Symbol("@accesses") || (lastarg isa QuoteNode && lastarg.value == Symbol("@accesses"))
                elseif macroref isa GlobalRef
                    is_access |= macroref.name == Symbol("@access")
                    is_accesses |= macroref.name == Symbol("@accesses")
                end
                (is_access || is_accesses) && return nothing
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
    @access obj eff reg

Declare one access inside a `@task` body.

# Arguments
- `obj`: Object being accessed.
- `eff`: Effect instance (`Read()`, `Write()`, `ReadWrite()`, `Reduce(op)`).
- `reg`: Region instance (`Whole()`, `Block(...)`, `Key(...)`, ...).

# Notes
- Valid only inside `@task`.
"""
macro access(obj, eff, reg)
    error("@access is only valid inside @task")
end

"""
    @accesses begin
        (obj1, eff1, reg1)
        (obj2, eff2, reg2)
        ...
    end

Declare multiple accesses inside a `@task` body.

Each entry must be a 3-tuple `(obj, eff, reg)`.
"""
macro accesses(block)
    error("@accesses is only valid inside @task")
end

"""
    @spawn expr

Append task expression `expr` to the current `@dag` builder.

# Notes
- `expr` should evaluate to a `TaskSpec` (or compatible value accepted by
  `push!` on `DAG`).
- Valid only within `@dag`.
"""
macro spawn(expr)
    return esc(:(push!(__parable_builder, $(expr))))
end

"""
    @dag begin
        ...
    end

Create a DAG builder context, collect tasks appended via `@spawn`, and return a
finalized `DAG`.

# Example
```julia
dag = Parable.@dag begin
    Parable.@spawn Parable.@task "t1" begin
        ...
    end
end
```
"""
macro dag(block)
    builder = gensym(:builder)
    return quote
        local $(builder) = DAG()
        let $(esc(:__parable_builder)) = $(builder)
            $(esc(block))
        end
        finalize!($(builder))
    end
end
