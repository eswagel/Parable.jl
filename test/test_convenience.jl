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

    # Allow multiple tasks per block.
    obj[] = 0
    dag2 = detangle_foreach(blocks) do r, i
        tasks = TaskSpec[]
        push!(tasks, Detangle.@task "a-$i" begin
            Detangle.@access obj Write() Whole()
            obj[] += 1
        end)
        push!(tasks, Detangle.@task "b-$i" begin
            Detangle.@access obj Write() Whole()
            obj[] += 1
        end)
        tasks
    end
    execute_serial!(dag2)
    @test obj[] == 2 * length(blocks)

    # detangle_map
    data = collect(1:10)
    blocks2 = eachblock(length(data), 4)
    dag_map, out = detangle_map(data, blocks2, x -> x * 2)
    execute_serial!(dag_map)
    @test out == data .* 2

    # detangle_mapreduce
    dag_red, acc = detangle_mapreduce(data, blocks2, +, x -> x * x)
    execute!(dag_red; backend=:threads, reduce_strategy=:privatize)
    @test acc[1] == sum(x * x for x in data)
end
