using Documenter: Documenter, makedocs, deploydocs, DocMeta
using DocumenterCodeBlocks

# The demo API the manual demonstrates reference links/tooltips against is
# evaluated INTO the DocumenterCodeBlocks module — nothing ships with the
# package. See docs/demo.jl.
if !isdefined(DocumenterCodeBlocks, :greet)
    Base.include(DocumenterCodeBlocks, joinpath(@__DIR__, "demo.jl"))
end

# Make the (unexported) demo names available inside docstring jldoctests.
DocMeta.setdocmeta!(
    DocumenterCodeBlocks,
    :DocTestSetup,
    :(import DocumenterCodeBlocks: greet, add_numbers, MyType, foo);
    recursive = true,
)

# When run under docs/liveserver.jl, Revise picks up edits to the plugin source
# (src/) between rebuilds triggered by LiveServer.
const liveserver = "liveserver" in ARGS
if liveserver
    using Revise
    Revise.revise()
end

makedocs(
    sitename = "DocumenterCodeBlocks",
    format = Documenter.HTML(
        edit_link = "main",
        canonical = "https://fredrikekre.github.io/DocumenterCodeBlocks.jl",
        # No `assets=` needed — CodeBlocks injects its own CSS/JS automatically,
        # and no `prerender`/node either: Julia is highlighted with JuliaSyntax.
    ),
    repo = Documenter.Remotes.GitHub("fredrikekre", "DocumenterCodeBlocks.jl"),
    modules = [DocumenterCodeBlocks],
    plugins = [
        CodeBlocks(),
    ],
    pages = [
        "Home" => "index.md",
        "Syntax highlighting" => "highlighting.md",
        "Line numbers" => "linenumbers.md",
        "Reference links & tooltips" => "references.md",
        "Docstring warnings" => "warnings.md",
        "API reference" => "api.md",
    ],
)

if !liveserver
    deploydocs(
        repo = "github.com/fredrikekre/DocumenterCodeBlocks.jl.git",
        devbranch = "main",
        push_preview = true,
    )
end
