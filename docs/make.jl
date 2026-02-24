using Documenter
using Detangle

# Set pretty URLs on CI (needed for GitHub Pages), but keep local builds working.
pretty = get(ENV, "CI", "false") == "true"

makedocs(
    sitename = "Detangle.jl",
    modules = [Detangle],
    format = Documenter.HTML(
        prettyurls = pretty,
        assets = String[],
    ),
    checkdocs = :exports,
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Manual" => [
            "Overview" => "manual/overview.md",
        ],
        "Tutorials" => [
            "Overview" => "tutorials/overview.md",
        ],
        "Comparison" => "comparison.md",
    ],
)

# Uncomment and set the repo URL to publish on GitHub Pages.
# deploydocs(
#     repo = "github.com/USER/Detangle.jl.git",
# )
