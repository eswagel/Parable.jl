@testset "dag building" begin
    obj = Ref(0)
    log = IOBuffer()

    function mk(name, eff)
        TaskSpec(name, () -> print(log, name, ";")) |> t -> add_access!(t, obj, eff, Whole())
    end

    t1 = mk("t1", Write())
    t2 = mk("t2", Read())
    t3 = mk("t3", Read())

    dag = DAG()
    push!(dag, t1)
    push!(dag, t2)
    push!(dag, t3)
    finalize!(dag)

    @test length(dag.edges) == 3
    @test dag.edges[1] == [2, 3]  # writer before readers
    @test isempty(dag.edges[2])
    @test isempty(dag.edges[3])

    @test dag.indeg == [0, 1, 1]

    # No conflicts case
    dag2 = DAG()
    push!(dag2, mk("r1", Read()))
    push!(dag2, mk("r2", Read()))
    finalize!(dag2)
    @test dag2.indeg == [0, 0]
    @test all(isempty, dag2.edges)

    # Parallel reductions allowed should drop edge
    dag3 = DAG()
    push!(dag3, mk("r3", Reduce(+)))
    push!(dag3, mk("r4", Reduce(+)))
    finalize!(dag3; can_parallel_reduce=true)
    @test dag3.indeg == [0, 0]
    @test all(isempty, dag3.edges)

    # Empty DAG finalization should no-op cleanly
    dag4 = DAG()
    finalize!(dag4)
    @test isempty(dag4.tasks)
    @test isempty(dag4.edges)
    @test isempty(dag4.indeg)
end
