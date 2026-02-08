using Detangle

include(joinpath(@__DIR__, "md_utils.jl"))

# Simplified MD demo: per-block force/integration tasks with spatial binning.
# Tasks declare which arrays/regions they read and write; Detangle uses that
# information to order dependent work and expose safe parallelism.

# === Parameters ===
# n: number of particles.
# box: side length of the square domain.
# n_cells_x/n_cells_y: spatial bins for neighbor lookup (more cells => fewer particles per cell).
# n_particles_per_thread: number of particles per task block (smaller => more tasks).
# dt: timestep size for integration.
# particle_radius: hard-sphere radius used for collision checks.
# cutoff: interaction radius (set to 2x particle_radius).
# k_spring: stiffness for the hard-sphere penalty force.
# speed_mean/speed_std: mean and stddev of initial speed; direction is random.
# steps: number of simulation steps to run.
# save_frames: toggle writing CSV frames for animation.
# frame_stride: save every Nth frame when save_frames=true.
# progress_stride: print progress every N steps.
n = 500
box = 10.0
n_particles_per_thread = 10
dt = 0.005
particle_radius = 0.2
cutoff = 2 * particle_radius
n_cells_x = n_cells_y = ceil(Int, box / cutoff)
k_spring = -10.0
speed_mean = 1.0
speed_std = 0.2
steps = 5000
save_frames = true
frame_stride = 10
progress_stride = 50
output_dir = joinpath(@__DIR__, "output")

println("initializing particles...")
posx, posy, velx, vely, forcex, forcey, blocks = init_particles_simple(
    n,
    box;
    block_size=n_particles_per_thread,
    speed_mean=speed_mean,
    speed_std=speed_std,
)
blocks = particle_blocks(n, n_particles_per_thread)
cutoff2 = cutoff * cutoff
soft = 1.0e-6
# Spatial bins for neighbor lookup.
cell_size = box / max(n_cells_x, n_cells_y)
neighbor_radius = ceil(Int, cutoff / cell_size)
cells = [Int[] for _ in 1:(n_cells_x * n_cells_y)]
cell_of = zeros(Int, n)
neighbors = [Int[] for _ in 1:(n_cells_x * n_cells_y)]
build_neighbor_cells!(neighbors, n_cells_x, n_cells_y, neighbor_radius)
bin_ctx = init_bin_context(n_cells_x * n_cells_y)

function apply_bounce!(x, v, box)
    # Reflect off walls to keep particles in-bounds.
    if !isfinite(x) || !isfinite(v)
        return x, v
    end
    while x < 0 || x > box
        if x < 0
            x = -x
            v = -v
        elseif x > box
            x = 2 * box - x
            v = -v
        end
    end
    return x, v
end

# Compute hard-sphere penalty forces using spatial bins for neighbor lookup.
function accumulate_forces!(r, cell_of, neighbors, cells, posx, posy, forcex, forcey, box, cutoff2, soft, particle_radius, k_spring)
    for i in r
        xi = posx[i]
        yi = posy[i]
        fx = 0.0
        fy = 0.0
        cid = cell_of[i]
        for ncell in neighbors[cid]
            for j in cells[ncell]
                j == i && continue
                dx = posx[j] - xi
                dy = posy[j] - yi
                if dx > box / 2
                    dx -= box
                elseif dx < -box / 2
                    dx += box
                end
                if dy > box / 2
                    dy -= box
                elseif dy < -box / 2
                    dy += box
                end
                r2 = dx * dx + dy * dy
                if r2 < cutoff2
                    r = sqrt(max(r2, 1.0e-6))
                    overlap = 2 * particle_radius - r
                    if overlap > 0
                        f = k_spring * overlap / r
                        fx += f * dx
                        fy += f * dy
                    end
                end
            end
        end
        forcex[i] = fx
        forcey[i] = fy
    end
end

function integrate_position!(r, posx, posy, velx, vely, forcex, forcey, dt, box)
    # Velocity-Verlet position update (half-step velocity + full position).
    for i in r
        velx[i] += 0.5 * dt * forcex[i]
        vely[i] += 0.5 * dt * forcey[i]
        posx[i], velx[i] = apply_bounce!(posx[i] + dt * velx[i], velx[i], box)
        posy[i], vely[i] = apply_bounce!(posy[i] + dt * vely[i], vely[i], box)
    end
end

function integrate_velocity!(r, velx, vely, forcex, forcey, dt)
    # Finish the velocity half-step after recomputing forces.
    for i in r
        velx[i] += 0.5 * dt * forcex[i]
        vely[i] += 0.5 * dt * forcey[i]
    end
end

println("building DAG...")
# The DAG is built once and reused each step. Each block contributes four tasks:
#   1) forces-$bi: compute forces for particles in r using spatial bins.
#   2) integrate-pos-$bi: advance positions with a half-step velocity update.
#   3) forces2-$bi: recompute forces after positions update.
#   4) integrate-vel-$bi: finish the velocity update.
# Access annotations describe which regions are read or written so Detangle can
# order dependent tasks and run independent blocks in parallel.
dag = Detangle.@dag begin
    Detangle.@spawn Detangle.@task "bin-1" begin
        Detangle.@access posx Read() Whole()
        Detangle.@access posy Read() Whole()
        Detangle.@access cells Write() Whole()
        Detangle.@access cell_of Write() Whole()
        # Parallel binning builds per-cell particle lists.
        bin_particles_auto!(cells, cell_of, posx, posy, box, n_cells_x, n_cells_y, bin_ctx)
    end
    for (bi, r) in enumerate(blocks)
        Detangle.@spawn Detangle.@task "forces-$bi" begin
            Detangle.@access posx Read() Whole()
            Detangle.@access posy Read() Whole()
            Detangle.@access cells Read() Whole()
            Detangle.@access cell_of Read() Whole()
            Detangle.@access neighbors Read() Whole()
            Detangle.@access forcex Write() Block(r)
            Detangle.@access forcey Write() Block(r)
            accumulate_forces!(r, cell_of, neighbors, cells, posx, posy, forcex, forcey, box, cutoff2, soft, particle_radius, k_spring)
        end
        Detangle.@spawn Detangle.@task "integrate-pos-$bi" begin
            Detangle.@access posx ReadWrite() Block(r)
            Detangle.@access posy ReadWrite() Block(r)
            Detangle.@access velx ReadWrite() Block(r)
            Detangle.@access vely ReadWrite() Block(r)
            Detangle.@access forcex Read() Block(r)
            Detangle.@access forcey Read() Block(r)
            integrate_position!(r, posx, posy, velx, vely, forcex, forcey, dt, box)
        end
    end
    Detangle.@spawn Detangle.@task "bin-2" begin
        Detangle.@access posx Read() Whole()
        Detangle.@access posy Read() Whole()
        Detangle.@access cells Write() Whole()
        Detangle.@access cell_of Write() Whole()
        bin_particles_auto!(cells, cell_of, posx, posy, box, n_cells_x, n_cells_y, bin_ctx)
    end
    for (bi, r) in enumerate(blocks)
        Detangle.@spawn Detangle.@task "forces2-$bi" begin
            Detangle.@access posx Read() Whole()
            Detangle.@access posy Read() Whole()
            Detangle.@access cells Read() Whole()
            Detangle.@access cell_of Read() Whole()
            Detangle.@access neighbors Read() Whole()
            Detangle.@access forcex Write() Block(r)
            Detangle.@access forcey Write() Block(r)
            accumulate_forces!(r, cell_of, neighbors, cells, posx, posy, forcex, forcey, box, cutoff2, soft, particle_radius, k_spring)
        end
        Detangle.@spawn Detangle.@task "integrate-vel-$bi" begin
            Detangle.@access velx ReadWrite() Block(r)
            Detangle.@access vely ReadWrite() Block(r)
            Detangle.@access forcex Read() Block(r)
            Detangle.@access forcey Read() Block(r)
            integrate_velocity!(r, velx, vely, forcex, forcey, dt)
        end
    end
end

println("tasks: ", length(dag.tasks))

println("starting simulation...")
if save_frames
    mkpath(output_dir)
    for path in readdir(output_dir; join=true)
        if occursin(r"frame_\\d+\\.csv$", path)
            rm(path)
        end
    end
end
for step in 1:steps
    execute_threads!(dag)

    if step % progress_stride == 0 || step == 1 || step == steps
        println("step ", step, "/", steps)
    end

    if save_frames && (step % frame_stride == 0)
        mkpath(output_dir)
        path = joinpath(output_dir, "frame_" * lpad(string(step), 4, '0') * ".csv")
        write_frame_csv(path, posx, posy)
    end
end

println("completed ", steps, " steps with ", 4 * length(blocks) + 2, " tasks/step")
println("frames written to ", output_dir)
include(joinpath(@__DIR__, "tools", "build_md_animation.jl"))