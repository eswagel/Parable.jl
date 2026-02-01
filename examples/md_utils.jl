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
