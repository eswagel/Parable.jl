@testset "effects" begin
    @test !is_writeish(Read())
    @test is_writeish(Write())
    @test is_writeish(ReadWrite())
    @test is_writeish(Reduce(+))

    @test !is_reduce(Read())
    @test is_reduce(Reduce(+))
    @test reduce_op(Reduce(*)) === (*)
end
