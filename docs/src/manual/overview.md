# Manual Overview

Detangle models parallel work as tasks plus declared accesses.

## Core concepts

- `TaskSpec`: a task name, access metadata, and a zero-argument thunk.
- `Access`: `(object, effect, region)` metadata used for conflict analysis.
- `DAG`: tasks plus dependency edges inferred from access conflicts.
- Backends: serial and threaded execution of the same finalized DAG.

## Effects and regions

Effects describe intent:

- `Read()`
- `Write()`
- `ReadWrite()`
- `Reduce(op)`

Regions scope where the effect applies:

- `Whole()`
- `Block(r::UnitRange)`
- `Key(k)`
- `Tile(I, J)`
- `IndexSet(idxs)`

The scheduler uses object identity + region overlap + effects to determine dependencies.

## Building DAGs

The macro workflow is the main entry point:

```julia
using Detangle

x = rand(100)
y = similar(x)
blocks = eachblock(length(x), 25)

dag = Detangle.@dag begin
    for (i, r) in enumerate(blocks)
        Detangle.@spawn Detangle.@task "scale-$i" begin
            Detangle.@access x Read() Block(r)
            Detangle.@access y Write() Block(r)
            @inbounds for idx in r
                y[idx] = 2x[idx]
            end
        end
    end
end

execute_threads!(dag)
```

There are also convenience builders such as `detangle_foreach`, `detangle_map`, and `detangle_mapreduce`.

## Debugging and inspection

- `print_dag(dag)`: print edge structure.
- `explain_conflict(taskA, taskB)`: inspect why two tasks conflict.

## API reference

```@autodocs
Modules = [Detangle]
Order   = [:module, :type, :function, :macro]
```
