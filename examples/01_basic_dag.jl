using Parable

obj = Ref(0)

# A simple three-task chain over the same object.
dag = Parable.@dag begin
    # First task writes a fresh value.
    Parable.@spawn Parable.@task "init" begin
        Parable.@accesses begin
            (obj, Write(), Whole())
        end
        obj[] = 1
    end

    # Second task mutates the same object.
    Parable.@spawn Parable.@task "bump" begin
        Parable.@accesses begin
            (obj, ReadWrite(), Whole())
        end
        obj[] += 1
    end

    # Final task reads the result.
    Parable.@spawn Parable.@task "read" begin
        Parable.@accesses begin
            (obj, Read(), Whole())
        end
        println("value = ", obj[])
    end
end

# Print the dependency structure, then run in a deterministic order.
print_dag(dag);
execute_serial!(dag); 
execute_threads!(dag);  # Can also run with threads
