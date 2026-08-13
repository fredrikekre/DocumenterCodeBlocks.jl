module DocumenterCodeBlocks

import Documenter

export CodeBlocks

# ---------------------------------------------------------------------------
# Plugin configuration
# ---------------------------------------------------------------------------

# The meta state a code block sees at its position on the page: the module
# reference resolution happens in, the line-numbering mode, and the block's
# series name (`@example name`, `@repl name`, `jldoctest name`, or the second
# fence token of a plain block) for `line_counter = :named`.
struct BlockMeta
    mod::Module
    line_counter::Symbol   # :restart | :continue | :named
    name::Union{String, Nothing}
end
BlockMeta(mod::Module, line_counter::Symbol) = BlockMeta(mod, line_counter, nothing)

"""
    CodeBlocks(; languages=["julia"], reference_links=true, popups=true, external_links=true, line_numbers=true, repl_line_numbers=true, min_lines=1, line_counter=:restart)

Documenter plugin that enhances code blocks with syntax highlighting, line
numbers / linkable lines, and reference links — all in a single pass. Julia is
highlighted locally with JuliaSyntax (including `julia-repl`/`jldoctest`
blocks), so no node/`prerender` is needed.

- `languages`: which code-block languages to process.
- `reference_links`: wrap identifiers that name a documented object in a link to
  its docstring. Macro names link too. Names in binding positions — left of
  `=`, function parameters, loop variables, … — are not uses and never link.
- `popups`: doxygen-style hover tooltips on reference links, embedded per page
  (no fetching): the target's signature and the docstring's first sentence.
  When a reference matches several documented methods (a bare identifier, a
  splatted call, …) the tooltip instead lists all candidate signatures to pick
  from. Requires `reference_links=true`.
- `external_links`: when a name is not documented locally and a
  [DocumenterInterLinks](https://github.com/JuliaDocs/DocumenterInterLinks.jl)
  `InterLinks` plugin is passed to `makedocs`, link it to the external
  documentation (the same inventories `@extref` uses — no extra configuration
  needed). External links are marked with a small ↗ and their tooltip names the
  project they link to. Requires `reference_links=true`.
- `line_numbers`: add the line-number gutter + linkable lines. When `false`, blocks
  are still highlighted (and linked) but rendered without a gutter.
- `repl_line_numbers`: also add the gutter to REPL transcripts (`julia-repl`
  blocks and REPL-style `jldoctest`s). Requires `line_numbers=true`.
- `min_lines`: blocks with fewer lines get an id + permalink but no gutter
  (the default numbers every block, including one-liners).
- `line_counter`: the default line-counter mode for every page — `:restart`,
  `:continue`, or `:named` (see the `@codeblocks` block below, which overrides
  it per page, positionally).

Reference resolution follows the page's `@meta CurrentModule` **positionally**,
exactly like `@ref`: the module in effect at a block's position applies to that
block, and code blocks inside a docstring resolve in the docstring's own module.

Pages can configure the plugin locally with an `@codeblocks` block:

````markdown
```@codeblocks
line_counter = :continue
```
````

- `line_counter`: `:restart` (default) numbers every block from 1;
  `:continue` carries one running line counter across the page's code blocks
  (`julia`, `julia-repl`, executed `@repl`), tutorial-style; `:named` keeps
  one counter **per named series** — blocks sharing a name (`@example name`,
  `@repl name`, `jldoctest name`, or a second fence token like
  ` ```julia name `) continue each other, while unnamed blocks restart. Like
  `@meta`, the setting applies from its position to the end of the page (or
  the next `@codeblocks` block). Blocks inside docstrings are their own page:
  they always start at 1 and do not advance any counter.

The first code block of a docstring — the signature header — gets no line
numbers or permalink (headers aren't always valid Julia, e.g. `f(x[, y])`),
but the argument and return types in it link to their docstrings; the
documented name itself and the parameter names stay plain. Throughout a
docstring, references with the enclosing docstring among their candidate
targets are not linked — the reader is already there — while calls whose
arity resolves to a different documented method still link.

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
    external_links::Bool
    line_numbers::Bool
    repl_line_numbers::Bool
    min_lines::Int
    line_counter::Symbol   # default line-counter mode: :restart | :continue | :named
    # Internal: crc32c hashes of the sources of `jldoctest`-fenced blocks, collected
    # before RenderDocument rewrites the fence to julia/julia-repl. Used to apply the
    # script-style `# output` split only to real doctests (like Documenter does).
    jldoctests::Set{UInt32}
    # Internal: per-block metadata collected positionally from each page's AST
    # (ScanStep): page key → (block kind, source hash) → FIFO queue of one entry
    # per occurrence, in document order. Gives every block the meta state AT ITS
    # POSITION — the resolution module (`@meta CurrentModule`, or the docstring's
    # own module) and the line-counter mode (`@codeblocks line_counter`) — the
    # way Documenter itself applies meta positionally for `@ref`/`@docs`.
    blockmeta::Dict{String, Dict{Tuple{Symbol, UInt32}, Vector{BlockMeta}}}
    # Internal: dedup keys of already-emitted "CodeBlocks: " build warnings, so
    # each extraction problem is reported once per build (not per page/reference).
    warned::Set{String}
end
function CodeBlocks(;
        languages = ["julia"], reference_links = true, popups = true, external_links = true,
        line_numbers = true, repl_line_numbers = true, min_lines = 1, line_counter = :restart,
    )
    line_counter isa Symbol && line_counter in (:restart, :continue, :named) || throw(
        ArgumentError(
            "CodeBlocks: invalid `line_counter` value `$(repr(line_counter))`; " *
                "expected :restart, :continue, or :named",
        ),
    )
    return CodeBlocks(
        languages, reference_links, popups, external_links, line_numbers, repl_line_numbers,
        min_lines, line_counter,
        Set{UInt32}(), Dict{String, Dict{Tuple{Symbol, UInt32}, Vector{BlockMeta}}}(),
        Set{String}(),
    )
end

include("split.jl")
include("render.jl")
include("juliasyntax.jl")
include("references.jl")
include("pipeline.jl")
include("assets.jl")

end # module DocumenterCodeBlocks
