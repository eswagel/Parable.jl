using Random

struct Particle
    x::Float64
    y::Float64
    vx::Float64
    vy::Float64
end

function cell_index(cx, cy, nx)
    return (cy - 1) * nx + cx
end

function cell_id_from_pos(x, y, box, nx, ny)
    if !isfinite(x) || !isfinite(y)
        error("non-finite position: x=$(x), y=$(y)")
    end
    xw = clamp(x, 0.0, box - eps(box))
    yw = clamp(y, 0.0, box - eps(box))
    cx = floor(Int, (xw / box) * nx) + 1
    cy = floor(Int, (yw / box) * ny) + 1
    cx = clamp(cx, 1, nx)
    cy = clamp(cy, 1, ny)
    return cell_index(cx, cy, nx)
end

function neighbor_cells(nx, ny, radius)
    n = nx * ny
    neighbors = [Int[] for _ in 1:n]
    for cy in 1:ny
        for cx in 1:nx
            c = cell_index(cx, cy, nx)
            for dy in -radius:radius
                for dx in -radius:radius
                    nxp = mod(cx - 1 + dx, nx) + 1
                    nyp = mod(cy - 1 + dy, ny) + 1
                    push!(neighbors[c], cell_index(nxp, nyp, nx))
                end
            end
        end
    end
    return neighbors
end

function build_neighbor_cells!(neighbors, nx, ny, radius)
    for v in neighbors
        empty!(v)
    end
    for cy in 1:ny
        for cx in 1:nx
            c = cell_index(cx, cy, nx)
            for dy in -radius:radius
                for dx in -radius:radius
                    nxp = mod(cx - 1 + dx, nx) + 1
                    nyp = mod(cy - 1 + dy, ny) + 1
                    push!(neighbors[c], cell_index(nxp, nyp, nx))
                end
            end
        end
    end
    return neighbors
end

function particle_blocks(n, block_size)
    return [i:min(i + block_size - 1, n) for i in 1:block_size:n]
end

function bin_particles!(cells, cell_of, posx, posy, box, nx, ny)
    for c in cells
        empty!(c)
    end
    for i in eachindex(posx)
        cid = cell_id_from_pos(posx[i], posy[i], box, nx, ny)
        cell_of[i] = cid
        push!(cells[cid], i)
    end
    return cells, cell_of
end

function bin_particles_parallel!(cells, cell_of, posx, posy, box, nx, ny)
    n = length(posx)
    ncells = nx * ny

    nt = Threads.maxthreadid()
    local_counts = [zeros(Int, ncells) for _ in 1:nt]

    Threads.@threads for i in 1:n
        tid = Threads.threadid()
        cid = cell_id_from_pos(posx[i], posy[i], box, nx, ny)
        cell_of[i] = cid
        local_counts[tid][cid] += 1
    end

    counts = zeros(Int, ncells)
    for t in 1:nt
        counts .+= local_counts[t]
    end

    offsets = zeros(Int, ncells)
    total = 0
    for c in 1:ncells
        offsets[c] = total
        total += counts[c]
    end

    flat = Vector{Int}(undef, total)

    # Compute per-thread write offsets without contention.
    local_offsets = [copy(offsets) for _ in 1:nt]
    for t in 1:nt
        for c in 1:ncells
            offset = 0
            for k in 1:t-1
                offset += local_counts[k][c]
            end
            local_offsets[t][c] += offset
        end
    end

    Threads.@threads for i in 1:n
        tid = Threads.threadid()
        cid = cell_of[i]
        idx = local_offsets[tid][cid] + 1
        local_offsets[tid][cid] = idx
        flat[idx] = i
    end

    for c in 1:ncells
        start = offsets[c] + 1
        stop = offsets[c] + counts[c]
        if stop < start
            empty!(cells[c])
        else
            cells[c] = flat[start:stop]
        end
    end

    return cells, cell_of
end

mutable struct BinContext
    flat::Vector{Int}
    counts::Vector{Int}
    offsets::Vector{Int}
    local_counts::Vector{Vector{Int}}
    local_offsets::Vector{Vector{Int}}
end

function init_bin_context(ncells)
    nt = Threads.maxthreadid()
    BinContext(Int[], zeros(Int, ncells), zeros(Int, ncells),
        [zeros(Int, ncells) for _ in 1:nt],
        [zeros(Int, ncells) for _ in 1:nt])
end

function bin_particles_parallel!(cells, cell_of, posx, posy, box, nx, ny, ctx::BinContext)
    n = length(posx)
    ncells = nx * ny

    length(ctx.counts) == ncells || (ctx.counts = zeros(Int, ncells))
    length(ctx.offsets) == ncells || (ctx.offsets = zeros(Int, ncells))

    nt = Threads.maxthreadid()
    if length(ctx.local_counts) != nt || length(ctx.local_counts[1]) != ncells
        ctx.local_counts = [zeros(Int, ncells) for _ in 1:nt]
        ctx.local_offsets = [zeros(Int, ncells) for _ in 1:nt]
    else
        for t in 1:nt
            fill!(ctx.local_counts[t], 0)
            fill!(ctx.local_offsets[t], 0)
        end
    end

    Threads.@threads for i in 1:n
        tid = Threads.threadid()
        cid = cell_id_from_pos(posx[i], posy[i], box, nx, ny)
        cell_of[i] = cid
        ctx.local_counts[tid][cid] += 1
    end

    fill!(ctx.counts, 0)
    for t in 1:nt
        ctx.counts .+= ctx.local_counts[t]
    end

    total = 0
    for c in 1:ncells
        ctx.offsets[c] = total
        total += ctx.counts[c]
    end

    if length(ctx.flat) < total
        resize!(ctx.flat, total)
    end

    for t in 1:nt
        for c in 1:ncells
            offset = 0
            for k in 1:t-1
                offset += ctx.local_counts[k][c]
            end
            ctx.local_offsets[t][c] = ctx.offsets[c] + offset
        end
    end

    Threads.@threads for i in 1:n
        tid = Threads.threadid()
        cid = cell_of[i]
        idx = ctx.local_offsets[tid][cid] + 1
        ctx.local_offsets[tid][cid] = idx
        ctx.flat[idx] = i
    end

    for c in 1:ncells
        start = ctx.offsets[c] + 1
        stop = ctx.offsets[c] + ctx.counts[c]
        if stop < start
            empty!(cells[c])
        else
            cells[c] = ctx.flat[start:stop]
        end
    end

    return cells, cell_of
end

function bin_particles_auto!(cells, cell_of, posx, posy, box, nx, ny, ctx::BinContext; threshold::Int=10_000)
    if length(posx) < threshold || Threads.maxthreadid() == 1
        return bin_particles!(cells, cell_of, posx, posy, box, nx, ny)
    end
    return bin_particles_parallel!(cells, cell_of, posx, posy, box, nx, ny, ctx)
end

function init_particles(n, box, nx, ny; seed=42, block_size=25, speed_mean=0.3, speed_std=0.1)
    Random.seed!(seed)
    posx = zeros(Float64, n)
    posy = zeros(Float64, n)
    velx = zeros(Float64, n)
    vely = zeros(Float64, n)
    forcex = zeros(Float64, n)
    forcey = zeros(Float64, n)

    for i in 1:n
        posx[i] = rand() * box
        posy[i] = rand() * box
        speed = max(0.0, speed_mean + speed_std * randn())
        angle = 2 * pi * rand()
        velx[i] = speed * cos(angle)
        vely[i] = speed * sin(angle)
    end

    cells = [Int[] for _ in 1:(nx * ny)]
    cell_of = zeros(Int, n)
    bin_particles!(cells, cell_of, posx, posy, box, nx, ny)
    blocks = particle_blocks(n, block_size)

    return posx, posy, velx, vely, forcex, forcey, cells, cell_of, blocks
end

function init_particles_simple(n, box; seed=42, block_size=25, speed_mean=0.3, speed_std=0.1)
    Random.seed!(seed)
    posx = zeros(Float64, n)
    posy = zeros(Float64, n)
    velx = zeros(Float64, n)
    vely = zeros(Float64, n)
    forcex = zeros(Float64, n)
    forcey = zeros(Float64, n)

    for i in 1:n
        posx[i] = rand() * box
        posy[i] = rand() * box
        speed = max(0.0, speed_mean + speed_std * randn())
        angle = 2 * pi * rand()
        velx[i] = speed * cos(angle)
        vely[i] = speed * sin(angle)
    end

    blocks = particle_blocks(n, block_size)
    return posx, posy, velx, vely, forcex, forcey, blocks
end

function particles_from_arrays(posx, posy, velx, vely)
    n = length(posx)
    particles = Vector{Particle}(undef, n)
    for i in 1:n
        particles[i] = Particle(posx[i], posy[i], velx[i], vely[i])
    end
    return particles
end

function write_frame_csv(path, posx, posy)
    open(path, "w") do io
        println(io, "x,y")
        for i in eachindex(posx)
            println(io, posx[i], ",", posy[i])
        end
    end
end
