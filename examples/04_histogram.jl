using Detangle
using Base.Threads

# Example: histogramming with reduction privatization.
# Each task processes a block of data and reduces into shared bins.

n = 2_500_000
nbins = 20
block_size = 125_000

# Gaussian-shaped data mapped into integer bins.
mu = (nbins + 1) / 2
sigma = nbins / 7
data = Vector{Int}(undef, n)
for i in 1:n
    x = mu + sigma * randn()
    bin = clamp(Int(round(x)), 1, nbins)
    data[i] = bin
end
blocks = eachblock(n, block_size)
# Extra work to make each update heavier without changing the bin.
@inline function extra_work(x::Int, i::Int)
    v = x + i
    @inbounds for _ in 1:8
        v = (v * 1664525 + 1013904223)
    end
    return v
end

hist = zeros(Int, nbins)

dag = detangle_foreach(blocks) do r, bi
    Detangle.@task "hist-$bi" begin
        Detangle.@access hist Reduce(+) Whole()
        @inbounds for i in r
            bin = data[i]
            extra_work(bin, i) # Adds compute without changing the bin, so parallelism has real work to speed up.
            Detangle.reduce_add!(hist, +, Whole(), bin, 1) # Route Reduce(+) into privatized buffers when enabled.
        end
    end
end

# Serial baseline.
expected = zeros(Int, nbins)
@inbounds for i in 1:n
    bin = data[i]
    extra_work(bin, i)
    expected[bin] += 1
end

println("running serialize...")
t_warm = @elapsed execute!(dag; backend=:serial, reduce_strategy=:serialize)
fill!(hist, 0)
println("warm-up serial = ", t_warm, "s")
t_serial = @elapsed execute!(dag; backend=:serial, reduce_strategy=:serialize)
ok_serial = hist == expected
println("serialize ok = ", ok_serial, " (", t_serial, "s)")

fill!(hist, 0)
println("running privatize...")
t_warm_par = @elapsed execute!(dag; backend=:threads, reduce_strategy=:privatize)
fill!(hist, 0)
println("warm-up privatize = ", t_warm_par, "s")
t_parallel = @elapsed execute!(dag; backend=:threads, reduce_strategy=:privatize)
ok_parallel = hist == expected
println("privatize ok = ", ok_parallel, " (", t_parallel, "s)")

println("threads = ", nthreads())
if ok_serial && ok_parallel
    if t_parallel > 0
        speedup = t_serial / t_parallel
        println("speedup = ", round(speedup; digits=2), "x")
    end
else
    println("results differ; check reduce_add! usage and Reduce annotations")
end

if nthreads() == 1
    println("note: set JULIA_NUM_THREADS>1 to see parallel speedups")
end

# Simple ASCII bar chart for tangible output.
function print_histogram(counts; width::Int=40)
    maxc = maximum(counts)
    maxc == 0 && (println("(empty)"); return)
    for (i, c) in enumerate(counts)
        bar_len = Int(round(width * c / maxc))
        bar = repeat("█", bar_len)
        println(lpad(string(i), 3), " | ", bar, " ", c)
    end
end

println("\nHistogram (privatize run):")
print_histogram(hist)
