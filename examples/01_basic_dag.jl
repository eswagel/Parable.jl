using Parables

obj = Ref(0)

# A simple three-task chain over the same object.
dag = Parables.@dag begin
    # First task writes a fresh value.
    Parables.@spawn Parables.@task "init" begin
        Parables.@accesses begin
            (obj, Write(), Whole())
        end
        obj[] = 1
    end

    # Second task mutates the same object.
    Parables.@spawn Parables.@task "bump" begin
        Parables.@accesses begin
            (obj, ReadWrite(), Whole())
        end
        obj[] += 1
    end

    # Final task reads the result.
    Parables.@spawn Parables.@task "read" begin
        Parables.@accesses begin
            (obj, Read(), Whole())
        end
        println("value = ", obj[])
    end
end

# Print the dependency structure, then run in a deterministic order.
print_dag(dag);
execute_serial!(dag); 
execute_threads!(dag);  # Can also run with threads
