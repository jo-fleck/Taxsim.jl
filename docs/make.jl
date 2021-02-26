using Taxsim
using Documenter

makedocs(;
    modules=[Taxsim],
    authors="Johannes Fleck <jofleck.work@gmail.com>",
    repo="https://github.com/jo-fleck/Taxsim.jl/blob/{commit}{path}#L{line}",
    sitename="Taxsim.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://jo-fleck.github.io/Taxsim.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/jo-fleck/Taxsim.jl",
)
