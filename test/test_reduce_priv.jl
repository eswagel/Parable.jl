@testset "reduce privatization" begin
    n = 10_000
    nbins = 16
    data = [rand(1:nbins) for _ in 1:n]
    block_size = 500
    blocks = [i:min(i + block_size - 1, n) for i in 1:block_size:n]

    hist = zeros(Int, nbins)

    dag = Detangle.@dag begin
        for (bi, r) in enumerate(blocks)
            Detangle.@spawn Detangle.@task "hist-$bi" begin
                Detangle.@access hist Reduce(+) Whole()
                for i in r
                    bin = data[i]
                    Detangle.reduce_add!(hist, +, Whole(), bin, 1)
                end
            end
        end
    end

    # Serial baseline
    expected = zeros(Int, nbins)
    for x in data
        expected[x] += 1
    end

    # Serialize strategy should still work.
    execute!(dag; backend=:serial, reduce_strategy=:serialize)
    @test hist == expected

    # Privatize: reset and ensure correctness matches baseline.
    fill!(hist, 0)
    execute!(dag; backend=:threads, reduce_strategy=:privatize)
    @test hist == expected
end
