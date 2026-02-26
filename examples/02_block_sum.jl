using Parable

# Example: block a vector into ranges, spawn one task per block, and write each
# block's sum into its own slot. This makes the parallel reduction safe and lets
# us compare against a serial loop with similar work.
n = 5_000_000
block_size = 250_000
data = collect(1:n)

# Work kernel used by both the DAG and the serial baseline.
function block_sum(data, r)
    acc = 0
    for idx in r
        v = data[idx]
        acc += v * v - v
    end
    acc
end

function serial_total(data, blocks)
    acc = 0
    for r in blocks
        acc += block_sum(data, r)
    end
    acc
end

# Precompute block ranges so each task declares a non-overlapping region.
blocks = eachblock(n, block_size)
partials = zeros(Int, length(blocks))

dag = parable_foreach(blocks) do r, bi
    # Each task reads its block and writes one slot in the partials array.
    Parable.@task "block-$bi" begin
        Parable.@access data Read() Block(r)
        Parable.@access partials Write() Key(bi)
        partials[bi] = block_sum(data, r)
    end
end

# Warm up JIT compilation so timing reflects execution cost, not compilation.
execute_threads!(dag)
sum(partials)
block_sum(data, blocks[1])

# Time the DAG run (parallel if you use execute_threads! and JULIA_NUM_THREADS>1).
# Run with e.g. `JULIA_NUM_THREADS=8` to see parallel speedups.
t_dag = @elapsed begin
    execute_threads!(dag)
    sum(partials)
end

# Time a plain serial baseline using the same work kernel.
total_plain = Ref(0)
t_plain = @elapsed begin
    total_plain[] = serial_total(data, blocks)
end

println("dag total = ", sum(partials), " (", t_dag, "s)")
println("plain total = ", total_plain[], " (", t_plain, "s)")
