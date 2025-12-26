@testset "conflicts" begin
    obj = Ref(0)
    other = Ref(1)

    read = access(obj, Read(), Whole())
    write = access(obj, Write(), Whole())
    write_other = access(other, Write(), Whole())
    block_read = access(obj, Read(), Block(1:2))
    block_write = access(obj, Write(), Block(3:4))

    @test !conflicts(write, write_other)  # different objects
    @test !conflicts(block_read, block_write)  # disjoint regions
    @test !conflicts(read, block_read)  # both reads
    @test conflicts(write, block_read)  # write-ish hits overlap

    red_a = access(obj, Reduce(+), Block(1:2))
    red_b = access(obj, Reduce(+), Block(1:2))
    red_c = access(obj, Reduce(*), Block(1:2))

    @test conflicts(red_a, red_b)  # default serialize reduces
    @test !conflicts(red_a, red_b; can_parallel_reduce=true)  # same op allowed
    @test conflicts(red_a, red_c; can_parallel_reduce=true)  # different ops still conflict

    # task_conflicts mirrors access conflicts
    t1 = TaskSpec("red1", () -> nothing)
    add_access!(t1, obj, Reduce(+), Block(1:2))
    t2 = TaskSpec("red2", () -> nothing)
    add_access!(t2, obj, Reduce(+), Block(1:2))
    @test task_conflicts(t1, t2)
    @test !task_conflicts(t1, t2; can_parallel_reduce=true)
end
