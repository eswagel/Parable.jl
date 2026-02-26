@testset "regions" begin
    @test ranges_overlap(1:3, 3:5)
    @test !ranges_overlap(1:2, 3:4)

    @test overlaps(Whole(), Key(:a))
    @test overlaps(Key(:a), Whole())
    @test overlaps(Key(:a), Key(:a))
    @test !overlaps(Key(:a), Key(:b))
    @test !overlaps(Key(:a), Block(1:3))

    @test overlaps(Block(1:3), Block(3:5))
    @test !overlaps(Block(1:2), Block(3:4))

    @test overlaps(Tile(1:2, 1:2), Tile(2:3, 2:3))
    @test !overlaps(Tile(1:2, 1:2), Tile(3:4, 3:4))

    @test overlaps(IndexSet([1, 5]), IndexSet([2, 3]))  # conservative default
    @test overlaps(Whole(), IndexSet([1]))  # Whole overlaps everything
    @test overlaps(IndexSet([1]), Tile(1:1, 1:1))  # conservative fallback

    # Explicit checks for mixed Key interactions
    @test overlaps(Key(:a), Whole())
    @test overlaps(Whole(), Key(:a))
    @test !overlaps(Key(:a), Block(1:1))

    # Generic fallback remains conservative true
    struct DummyRegion <: Parable.Region end
    @test overlaps(DummyRegion(), DummyRegion())
end
