#!/usr/bin/env julia

function parse_frame(path)
    lines = readlines(path)
    pts = Vector{Tuple{Float64, Float64}}(undef, length(lines) - 1)
    for (i, line) in enumerate(lines[2:end])
        xstr, ystr = split(line, ",")
        pts[i] = (parse(Float64, xstr), parse(Float64, ystr))
    end
    return pts
end

function build_animation_html(frame_paths, out_path; particle_radius=0.2)
    frames = Vector{Vector{Tuple{Float64, Float64}}}(undef, length(frame_paths))
    max_val = 0.0
    for (i, path) in enumerate(frame_paths)
        pts = parse_frame(path)
        frames[i] = pts
        for (x, y) in pts
            max_val = max(max_val, x, y)
        end
    end

    open(out_path, "w") do io
        println(io, "<!doctype html>")
        println(io, "<html><head><meta charset=\"utf-8\">")
        println(io, "<title>Detangle MD Animation</title>")
        println(io, "<style>")
        println(io, "body { margin: 0; font-family: sans-serif; background: #111; color: #eee; }")
        println(io, "#wrap { display: flex; align-items: center; justify-content: center; height: 100vh; }")
        println(io, "canvas { background: #000; border: 1px solid #333; }")
        println(io, "#hud { position: fixed; top: 12px; left: 12px; font-size: 12px; }")
        println(io, "</style></head><body>")
        println(io, "<div id=\"hud\">frame: <span id=\"frame\">0</span> / " * string(length(frames)) * "</div>")
        println(io, "<div id=\"wrap\"><canvas id=\"c\" width=\"600\" height=\"600\"></canvas></div>")
        println(io, "<script>")
        println(io, "const frames = [")
        for (i, pts) in enumerate(frames)
            print(io, "  [")
            for (j, (x, y)) in enumerate(pts)
                print(io, "[", x, ",", y, "]")
                j < length(pts) && print(io, ",")
            end
            println(io, i < length(frames) ? "]," : "]")
        end
        println(io, "];")
        println(io, "const maxVal = " * string(max_val) * ";")
        println(io, "const c = document.getElementById('c');")
        println(io, "const ctx = c.getContext('2d');")
        println(io, "const label = document.getElementById('frame');")
        println(io, "const particleRadius = " * string(particle_radius) * ";")
        println(io, "let f = 0;")
        println(io, "function draw() {")
        println(io, "  ctx.clearRect(0, 0, c.width, c.height);")
        println(io, "  ctx.fillStyle = '#0ff';")
        println(io, "  const scale = Math.min(c.width, c.height) / maxVal;")
        println(io, "  const radius = Math.max(1, particleRadius * scale);")
        println(io, "  const pts = frames[f];")
        println(io, "  for (let i = 0; i < pts.length; i++) {")
        println(io, "    const x = pts[i][0] * scale;")
        println(io, "    const y = pts[i][1] * scale;")
        println(io, "    ctx.beginPath();")
        println(io, "    ctx.arc(x, y, radius, 0, Math.PI * 2);")
        println(io, "    ctx.fill();")
        println(io, "  }")
        println(io, "  label.textContent = (f + 1).toString();")
        println(io, "  f = (f + 1) % frames.length;")
        println(io, "}")
        println(io, "setInterval(draw, 60);")
        println(io, "draw();")
        println(io, "</script></body></html>")
    end
end

out_dir = joinpath(@__DIR__, "..", "output")
frame_paths = sort(filter(p -> endswith(p, ".csv"), readdir(out_dir; join=true)))
isempty(frame_paths) && error("No CSV frames found in $(out_dir)")
out_path = joinpath(out_dir, "animate.html")
particle_radius = 0.2
example_path = joinpath(@__DIR__, "..", "03_molecular_dynamics.jl")
if isfile(example_path)
    for line in eachline(example_path)
        m = match(r"^\\s*particle_radius\\s*=\\s*([0-9.eE+-]+)", line)
        if m !== nothing
            particle_radius = parse(Float64, m.captures[1])
            break
        end
    end
end
for arg in ARGS
    if startswith(arg, "--radius=")
        particle_radius = parse(Float64, split(arg, "=", limit=2)[2])
    end
end

build_animation_html(frame_paths, out_path; particle_radius=particle_radius)
println("Wrote ", out_path, " (radius=", particle_radius, ")")
