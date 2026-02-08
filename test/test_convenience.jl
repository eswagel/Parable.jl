@testset "convenience helpers" begin
    blocks = eachblock(10, 3)
    @test blocks == [1:3, 4:6, 7:9, 10:10]

    obj = Ref(0)
    accesses = [(obj, Write(), Whole())]
    t = task_from_accesses("t", accesses, () -> (obj[] = 1))
    @test length(t.accesses) == 1

    dag = detangle_foreach(blocks) do r, i
        Detangle.@task "t-$i" begin
            Detangle.@access obj Write() Whole()
            obj[] += 1
        end
    end
    execute_serial!(dag)
    @test obj[] == length(blocks)
end
