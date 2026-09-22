using Taxsim
using Documenter

DocMeta.setdocmeta!(Taxsim, :DocTestSetup, :(using Taxsim); recursive = true)

makedocs(;
    modules = [Taxsim],
    authors = "Johannes Fleck <jofleck.work@gmail.com>",
    repo = Remotes.GitHub("jo-fleck", "Taxsim.jl"),
    sitename = "Taxsim.jl",
    # Internals are documented for maintainers but deliberately not in the manual.
    checkdocs = :exported,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://jo-fleck.github.io/Taxsim.jl",
        assets = String[],
    ),
    pages = ["Home" => "index.md"],
)

deploydocs(; repo = "github.com/jo-fleck/Taxsim.jl", devbranch = "master")
