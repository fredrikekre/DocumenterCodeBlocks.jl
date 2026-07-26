module DocumenterCodeBlocks

import Documenter

export CodeBlocks

# ---------------------------------------------------------------------------
# Plugin configuration
# ---------------------------------------------------------------------------

"""
    CodeBlocks(; languages=["julia"], reference_links=true, popups=true, line_numbers=true, repl_line_numbers=true, min_lines=1)

Documenter plugin that enhances code blocks with syntax highlighting, line
numbers / linkable lines, and reference links — all in a single pass. Julia is
highlighted locally with JuliaSyntax (including `julia-repl`/`jldoctest`
blocks), so no node/`prerender` is needed.

- `languages`: which code-block languages to process.
- `reference_links`: wrap identifiers that name a documented object in a link to
  its docstring.
- `popups`: doxygen-style hover tooltips on reference links, embedded per page
  (no fetching): the target's signature and the docstring's first sentence.
  When a reference matches several documented methods (a bare identifier, a
  splatted call, …) the tooltip instead lists all candidate signatures to pick
  from. Requires `reference_links=true`.
- `line_numbers`: add the line-number gutter + linkable lines. When `false`, blocks
  are still highlighted (and linked) but rendered without a gutter.
- `repl_line_numbers`: also add the gutter to REPL transcripts (`julia-repl`
  blocks and REPL-style `jldoctest`s). Requires `line_numbers=true`.
- `min_lines`: blocks with fewer lines get an id + permalink but no gutter
  (the default numbers every block, including one-liners).

The first code block of a docstring — the signature header — is only
syntax-highlighted: no line numbers, permalink, or reference links (headers
aren't always valid Julia, e.g. `f(x[, y])`). In the rest of a docstring's code
blocks, references that resolve back to the enclosing docstring itself are not
linked — the reader is already there — while calls whose arity resolves to a
different documented method still link.

Build warnings prefixed `CodeBlocks: ` nudge toward tooltip-friendly (and
generally better) docstrings: they fire — once per problem, and only for
docstrings some code block references — when a docstring lacks a leading
signature block or a prose first sentence, when the first sentence exceeds
200 characters, and when a call's arity matches no documented method.

Pass to `makedocs(plugins=[CodeBlocks()])`.
"""
struct CodeBlocks <: Documenter.Plugin
    languages::Vector{String}
    reference_links::Bool
    popups::Bool
    line_numbers::Bool
    repl_line_numbers::Bool
    min_lines::Int
    # Internal: crc32c hashes of the sources of `jldoctest`-fenced blocks, collected
    # before RenderDocument rewrites the fence to julia/julia-repl. Used to apply the
    # script-style `# output` split only to real doctests (like Documenter does).
    jldoctests::Set{UInt32}
    # Internal: dedup keys of already-emitted "CodeBlocks: " build warnings, so
    # each extraction problem is reported once per build (not per page/reference).
    warned::Set{String}
end
function CodeBlocks(; languages = ["julia"], reference_links = true, popups = true, line_numbers = true, repl_line_numbers = true, min_lines = 1)
    return CodeBlocks(languages, reference_links, popups, line_numbers, repl_line_numbers, min_lines, Set{UInt32}(), Set{String}())
end

include("split.jl")
include("render.jl")
include("juliasyntax.jl")
include("references.jl")
include("pipeline.jl")
include("assets.jl")

end # module DocumenterCodeBlocks
