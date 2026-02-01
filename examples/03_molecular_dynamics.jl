using Detangle

include(joinpath(@__DIR__, "md_utils.jl"))

# Simplified MD demo: per-block force and integrate tasks with rebinned cells.
n = 1000
box = 10.0
nx = 100
ny = 100
block_size = 10
dt = 0.005
cutoff = 2.0
epsilon = 0.01
sigma = 0.1
speed_mean = 0.0
speed_std = 0.0
steps = 500
save_frames = false
frame_stride = 1
progress_stride = 5
output_dir = joinpath(@__DIR__, "output")

println("initializing particles...")
posx, posy, velx, vely, forcex, forcey, cells, cell_of, blocks = init_particles(
    n,
    box,
    nx,
    ny;
    block_size=block_size,
    speed_mean=speed_mean,
    speed_std=speed_std,
)
blocks = particle_blocks(n, block_size)
cell_size = box / max(nx, ny)
neighbor_radius = ceil(Int, cutoff / cell_size)
neighbors = neighbor_cells(nx, ny, neighbor_radius)
cutoff2 = cutoff * cutoff
soft = 1.0e-6

function apply_bounce!(x, v, box)
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

function accumulate_forces!(r, cell_of, neighbors, cells, posx, posy, forcex, forcey, box, cutoff2, soft, epsilon, sigma)
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
                    r2 = max(r2, 1.0e-3)
                    inv_r2 = 1.0 / (r2 + soft)
                    sr2 = (sigma * sigma) * inv_r2
                    sr6 = sr2 * sr2 * sr2
                    sr12 = sr6 * sr6
                    f = 24.0 * epsilon * (2.0 * sr12 - sr6) * inv_r2
                    fx += f * dx
                    fy += f * dy
                end
            end
        end
        forcex[i] = fx
        forcey[i] = fy
    end
end

function integrate_position!(r, posx, posy, velx, vely, forcex, forcey, dt, box)
    for i in r
        velx[i] += 0.5 * dt * forcex[i]
        vely[i] += 0.5 * dt * forcey[i]
        posx[i], velx[i] = apply_bounce!(posx[i] + dt * velx[i], velx[i], box)
        posy[i], vely[i] = apply_bounce!(posy[i] + dt * vely[i], vely[i], box)
    end
end

function integrate_velocity!(r, velx, vely, forcex, forcey, dt)
    for i in r
        velx[i] += 0.5 * dt * forcex[i]
        vely[i] += 0.5 * dt * forcey[i]
    end
end

println("building force DAG...")
forces_dag = Detangle.@dag begin
    for (bi, r) in enumerate(blocks)
        Detangle.@spawn Detangle.@task "forces-$bi" begin
            Detangle.@access posx Read() Whole()
            Detangle.@access posy Read() Whole()
            Detangle.@access cell_of Read() Whole()
            Detangle.@access cells Read() Whole()
            Detangle.@access forcex Write() Block(r)
            Detangle.@access forcey Write() Block(r)
            accumulate_forces!(r, cell_of, neighbors, cells, posx, posy, forcex, forcey, box, cutoff2, soft, epsilon, sigma)
        end
    end
end

println("building integrate DAG...")
integrate_pos_dag = Detangle.@dag begin
    for (bi, r) in enumerate(blocks)
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
end

println("force tasks: ", length(forces_dag.tasks))
println("integrate-pos tasks: ", length(integrate_pos_dag.tasks))

integrate_vel_dag = Detangle.@dag begin
    for (bi, r) in enumerate(blocks)
        Detangle.@spawn Detangle.@task "integrate-vel-$bi" begin
            Detangle.@access velx ReadWrite() Block(r)
            Detangle.@access vely ReadWrite() Block(r)
            Detangle.@access forcex Read() Block(r)
            Detangle.@access forcey Read() Block(r)
            integrate_velocity!(r, velx, vely, forcex, forcey, dt)
        end
    end
end

println("integrate-vel tasks: ", length(integrate_vel_dag.tasks))

println("starting simulation...")
for step in 1:steps
    bin_particles!(cells, cell_of, posx, posy, box, nx, ny)
    execute_threads!(forces_dag)
    execute_threads!(integrate_pos_dag)
    bin_particles!(cells, cell_of, posx, posy, box, nx, ny)
    execute_threads!(forces_dag)
    execute_threads!(integrate_vel_dag)

    if step % progress_stride == 0 || step == 1 || step == steps
        println("step ", step, "/", steps)
    end

    if save_frames && (step % frame_stride == 0)
        mkpath(output_dir)
        path = joinpath(output_dir, "frame_" * lpad(string(step), 4, '0') * ".csv")
        write_frame_csv(path, posx, posy)
    end
end

println("completed ", steps, " steps with ", 3 * length(blocks), " tasks/step")
