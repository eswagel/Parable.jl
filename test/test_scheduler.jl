@testset "scheduler" begin
    obj = Ref(0)

    # DAG with ordering: t1 before t2 and t3
    log = Vector{String}()
    function mk_task(name, eff)
        TaskSpec(name, () -> push!(log, name)) |> t -> add_access!(t, obj, eff, Whole())
    end

    t1 = mk_task("t1", Write())
    t2 = mk_task("t2", Read())
    t3 = mk_task("t3", Read())

    dag = DAG()
    push!(dag, t1); push!(dag, t2); push!(dag, t3)
    finalize!(dag)

    execute_serial!(dag)
    println("Testing in serial:")
    println(log)
    idxs = Dict(name => findfirst(==(name), log) for name in log)
    @test idxs["t1"] < idxs["t2"]
    @test idxs["t1"] < idxs["t3"]

    # Threaded execution should respect same ordering constraints.
    empty!(log)
    execute_threads!(dag; nworkers=3)
    println("Testing in threads:")
    println(log)
    idxs = Dict(name => findfirst(==(name), log) for name in log)
    @test idxs["t1"] < idxs["t2"]
    @test idxs["t1"] < idxs["t3"]

    # DAG with no conflicts should run all tasks.
    log2 = Threads.Atomic{Int}(0)
    dag2 = DAG()
    push!(dag2, TaskSpec("a", () -> Threads.atomic_add!(log2, 1)))  # read-only implicit (no accesses)
    push!(dag2, TaskSpec("b", () -> Threads.atomic_add!(log2, 1)))
    finalize!(dag2)
    execute_threads!(dag2; nworkers=2)
    @test log2[] == 2

    # ReadWrite should enforce ordering versus reads.
    empty!(log)
    t4 = TaskSpec("rw", () -> push!(log, "rw"))
    add_access!(t4, obj, ReadWrite(), Whole())
    t5 = TaskSpec("r", () -> push!(log, "r"))
    add_access!(t5, obj, Read(), Whole())
    dag3 = DAG()
    push!(dag3, t4); push!(dag3, t5)
    finalize!(dag3)
    execute_serial!(dag3)
    idxs = Dict(name => findfirst(==(name), log) for name in log)
    @test idxs["rw"] < idxs["r"]

    # Backend dispatch and error
    @test execute!(dag; backend=:threads) === dag
    @test_throws ErrorException execute!(dag; backend=:bogus)

    # Empty DAG executes without error
    dag_empty = DAG()
    finalize!(dag_empty)
    @test execute_serial!(dag_empty) === dag_empty
    @test execute_threads!(dag_empty; nworkers=4) === dag_empty
    @test execute!(dag_empty; backend=:serial) === dag_empty
    @test execute!(dag_empty; backend=:threads, nworkers=1) === dag_empty

    # More workers than tasks still completes
    empty!(log)
    dag_small = DAG()
    push!(dag_small, TaskSpec("only", () -> push!(log, "only")))
    finalize!(dag_small)
    execute_threads!(dag_small; nworkers=8)
    @test log == ["only"]

    # reduce_strategy dispatch: serialize works, privatize errors for now
    @test execute!(dag; backend=:threads, reduce_strategy=:serialize) === dag
    @test_throws ErrorException execute!(dag; backend=:threads, reduce_strategy=:privatize)
end
