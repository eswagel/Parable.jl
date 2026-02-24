using Documenter
using Detangle

function tutorial_title(stem::String)
    pretty = replace(stem, r"^\d+_" => "")
    pretty = replace(pretty, "_" => " ")
    return titlecase(pretty)
end

function run_capture(cmd::Cmd)
    io = IOBuffer()
    proc = run(pipeline(ignorestatus(cmd), stdout=io, stderr=io))
    return String(take!(io)), success(proc)
end

function parse_frame_csv(path::String)
    lines = readlines(path)
    pts = Vector{Tuple{Float64, Float64}}(undef, max(0, length(lines) - 1))
    for (i, line) in enumerate(lines[2:end])
        xstr, ystr = split(line, ",")
        pts[i] = (parse(Float64, xstr), parse(Float64, ystr))
    end
    return pts
end

function write_md_animation_html(frame_paths::Vector{String}, out_path::String; particle_radius::Float64=0.12)
    frames = Vector{Vector{Tuple{Float64, Float64}}}(undef, length(frame_paths))
    max_val = 0.0
    for (i, path) in enumerate(frame_paths)
        pts = parse_frame_csv(path)
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

function tutorial_output_section(stem::String, examples_dir::String, generated_abs_dir::String)
    if stem == "03_molecular_dynamics"
        output_dir = joinpath(examples_dir, "output")
        gif_candidates = [
            joinpath(output_dir, "molecular_dynamics.gif"),
            joinpath(output_dir, "animate.gif"),
            joinpath(output_dir, "md_simulation.gif"),
        ]
        for gif in gif_candidates
            if isfile(gif)
                dst = joinpath(generated_abs_dir, "03_molecular_dynamics.gif")
                cp(gif, dst; force=true)
                return """
## Visualization

![Molecular dynamics animation](03_molecular_dynamics.gif)
"""
            end
        end

        frame_paths = sort(filter(p -> occursin(r"frame_\d+\.csv$", basename(p)),
            readdir(output_dir; join=true)))
        if !isempty(frame_paths)
            dst = joinpath(generated_abs_dir, "03_molecular_dynamics_animation.html")
            write_md_animation_html(frame_paths, dst; particle_radius=0.12)
            return """
## Visualization

Animation generated during docs build from MD frame CSVs.

```@raw html
<iframe src=\"03_molecular_dynamics_animation.html\" width=\"720\" height=\"760\" style=\"border:1px solid #d0d7de;\"></iframe>
```

[Open animation in a new tab](03_molecular_dynamics_animation.html)
"""
        end
        return "\n## Visualization\n\nNo animation artifact found. Run `examples/03_molecular_dynamics.jl` to generate frame CSVs in `examples/output/`.\n"
    end

    if stem == "04_histogram"
        repo_root = normpath(joinpath(examples_dir, ".."))
        cmd = Cmd(
            `julia --project=. examples/04_histogram.jl`;
            dir=repo_root,
            env=merge(ENV, Dict("JULIA_NUM_THREADS" => get(ENV, "JULIA_NUM_THREADS", "8"))),
        )
        output, ok = run_capture(cmd)
        output_path = joinpath(generated_abs_dir, "04_histogram_terminal_output.txt")
        write(output_path, output)
        output = strip(output)
        nthreads = get(ENV, "JULIA_NUM_THREADS", "8")
        header_cmd = "\$ JULIA_NUM_THREADS=$(nthreads) julia --project=. examples/04_histogram.jl"
        header = ok ? "```text\n$(header_cmd)\n" : "```text\n$(header_cmd) (failed)\n"
        return """
## Visualization

Real terminal output from running the histogram tutorial:

$header
$output
```
"""
    end

    return ""
end

function tutorial_markdown(stem::String, source::String, output_section::String)
    return """
# $(tutorial_title(stem))

This page is auto-generated from `examples/$(stem).jl`.

The tutorial code is rendered only (not executed during docs build).

```julia
$(source)
```
$output_section
"""
end

function build_tutorial_pages()
    docs_src_dir = joinpath(@__DIR__, "src")
    examples_dir = normpath(joinpath(@__DIR__, "..", "examples"))
    generated_rel_dir = "tutorials/generated"
    generated_abs_dir = joinpath(docs_src_dir, generated_rel_dir)
    mkpath(generated_abs_dir)

    # Remove stale generated tutorial pages so nav matches current examples/.
    for f in readdir(generated_abs_dir; join=true)
        isfile(f) && rm(f)
    end

    # Treat numbered top-level examples as tutorial sources.
    example_files = sort(filter(path -> occursin(r"^\d+_.*\.jl$", basename(path)),
        readdir(examples_dir; join=true)))

    tutorial_pages = Pair{String, String}["Overview" => "tutorials/overview.md"]
    for src in example_files
        stem = splitext(basename(src))[1]
        dst = joinpath(generated_abs_dir, "$(stem).md")
        output_section = tutorial_output_section(stem, examples_dir, generated_abs_dir)
        write(dst, tutorial_markdown(stem, read(src, String), output_section))
        push!(tutorial_pages, tutorial_title(stem) => "tutorials/generated/$(stem).md")
    end
    return tutorial_pages
end

# Set pretty URLs on CI (needed for GitHub Pages), but keep local builds working.
pretty = get(ENV, "CI", "false") == "true"
tutorial_pages = build_tutorial_pages()

makedocs(
    sitename = "Detangle.jl",
    modules = [Detangle],
    format = Documenter.HTML(
        prettyurls = pretty,
        edit_link = "main",
        assets = String[],
    ),
    checkdocs = :exports,
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Manual" => [
            "Overview" => "manual/overview.md",
            "Concepts and Semantics" => "manual/concepts.md",
            "API Reference" => "manual/api_reference.md",
        ],
        "Tutorials" => tutorial_pages,
        "Comparison" => "comparison.md",
    ],
)

deploydocs(
    repo = "github.com/eswagel/Detangle.jl.git",
    devbranch = "main",
)
