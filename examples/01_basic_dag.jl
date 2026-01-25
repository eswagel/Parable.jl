using Detangle

obj = Ref(0)

# A simple three-task chain over the same object.
dag = Detangle.@dag begin
    # First task writes a fresh value.
    Detangle.@spawn Detangle.@task "init" begin
        Detangle.@access obj Write() Whole()
        obj[] = 1
    end

    # Second task mutates the same object.
    Detangle.@spawn Detangle.@task "bump" begin
        Detangle.@access obj ReadWrite() Whole()
        obj[] += 1
    end

    # Final task reads the result.
    Detangle.@spawn Detangle.@task "read" begin
        Detangle.@access obj Read() Whole()
        println("value = ", obj[])
    end
end

# Print the dependency structure, then run in a deterministic order.
print_dag(dag);
execute_serial!(dag); 
execute_threads!(dag);  # Can also run with threads
