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
