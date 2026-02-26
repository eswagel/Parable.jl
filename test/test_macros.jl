@testset "macros" begin
    obj = Ref(0)

    dag = Parables.@dag begin
        Parables.@spawn Parables.@task "write" begin
            Parables.@access obj Write() Whole()
            obj[] = 1
        end
        Parables.@spawn Parables.@task "readwrite" begin
            Parables.@access obj ReadWrite() Whole()
            obj[] += 1
        end
    end

    @test isa(dag, DAG)
    @test dag.indeg == [0, 1]

    execute_serial!(dag)
    @test obj[] == 2
end

@testset "accesses block" begin
    obj = Ref(0)

    task = Parables.@task "write" begin
        Parables.@accesses begin
            (obj, Write(), Whole())
        end
        obj[] = 1
    end

    @test length(task.accesses) == 1
    @test isa(task.accesses[1].eff, Write)
    @test isa(task.accesses[1].reg, Whole)
end
