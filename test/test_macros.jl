@testset "macros" begin
    obj = Ref(0)

    dag = Detangle.@dag begin
        Detangle.@spawn Detangle.@task "write" begin
            Detangle.@access obj Write() Whole()
            obj[] = 1
        end
        Detangle.@spawn Detangle.@task "readwrite" begin
            Detangle.@access obj ReadWrite() Whole()
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

    task = Detangle.@task "write" begin
        Detangle.@accesses begin
            (obj, Write(), Whole())
        end
        obj[] = 1
    end

    @test length(task.accesses) == 1
    @test isa(task.accesses[1].eff, Write)
    @test isa(task.accesses[1].reg, Whole)
end
