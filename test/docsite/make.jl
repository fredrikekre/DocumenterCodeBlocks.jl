# Build the DocumenterCodeBlocks TEST docsite: the code-block zoo and the
# stress-test pages the Julia tests (and the Playwright suites) assert against.
#
# This is NOT the user documentation (that lives in docs/); it exists so the
# demo API — including deliberately degraded docstrings — never ships with the
# package or shows up in the real manual.
#
# Run standalone with:  julia --project=test/docsite test/docsite/make.jl
# (test/runtests.jl includes this file inside the test environment instead.)

using Documenter: Documenter, makedocs, DocMeta
using DocumenterCodeBlocks

# The demo API is evaluated INTO the DocumenterCodeBlocks module so anchors and
# tooltips read `DocumenterCodeBlocks.foo` — nothing here ships with the package.
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

makedocs(
    sitename = "DocumenterCodeBlocks testbed",
    root = @__DIR__,
    format = Documenter.HTML(
        edit_link = "main",
        # No `assets=` needed — CodeBlocks injects its own CSS/JS automatically,
        # and no `prerender`/node either: Julia is highlighted with JuliaSyntax.
        # (Under Pkg.test the active project has no version to infer for the
        # objects.inv inventory, so set one explicitly.)
        inventory_version = "0",
    ),
    repo = Documenter.Remotes.GitHub("fredrikekre", "DocumenterCodeBlocks.jl"),
    modules = [DocumenterCodeBlocks],
    plugins = [
        CodeBlocks(),
    ],
    pages = [
        "Home" => "index.md",
        "Code block zoo" => "zoo.md",
        "Big block" => "bigblock.md",
        "Skip cases" => "skipcases.md",
        "Reference links" => "references.md",
        "Doctest blocks" => "doctest-blocks.md",
        "Continued numbering" => "continued.md",
    ],
)
