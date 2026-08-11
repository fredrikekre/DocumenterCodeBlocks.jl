# DocumenterCodeBlocks.jl

A [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl) plugin that
enhances Julia code blocks:

- **[Line numbers and linkable lines](@ref linenumbers)**, GitHub style:
  every block gets a permalink, and clicking the gutter selects lines and puts
  a stable fragment like `#c-1a2b3c4d-L3-L7` in the URL.
- **[Reference links](@ref references)**: identifiers in code blocks that name
  a documented object link to its docstring — call-arity aware, so
  `foo(1, 2)` links to the `foo(a, b)` method documentation. Macro names
  link too.
- **[Hover tooltips](@ref tooltips)** on every reference link, doxygen style:
  the target's signature and a one-line summary, embedded at build time.
  Ambiguous references show the candidate-method list.
- **[Syntax highlighting](@ref highlighting)** of Julia code blocks at build
  time with [JuliaSyntax.jl](https://github.com/JuliaLang/JuliaSyntax.jl).
  Works for `julia`, `julia-repl`, `jldoctest`, and executed `@repl` blocks alike.
- **[Docstring-quality warnings](@ref warnings)** that nudge toward
  tooltip-friendly docstrings.

Every code block in this manual is rendered by the plugin — hover, click, and
select away.

## Installation

Install the package from the General registry:

```julia-repl
julia> import Pkg

julia> Pkg.add("DocumenterCodeBlocks")
```

## Usage

Add the plugin to your `docs/Project.toml` and pass it to `makedocs`:

```julia
using Documenter, DocumenterCodeBlocks

makedocs(
    sitename = "MyPackage",
    # ...
    plugins = [CodeBlocks()],
)
```

That is all — the CSS/JS assets are injected automatically and the default
[`Documenter.HTML`](https://documenter.juliadocs.org/stable/lib/public/#Documenter.HTML)
format needs no extra options. See [`CodeBlocks`](@ref) for configuration.

For unqualified names in code blocks to resolve to docstrings, set the page's
`CurrentModule` — exactly as for `@ref` links:

````markdown
```@meta
CurrentModule = MyPackage
```
````

## Status

Experimental. The plugin builds on Documenter internals beyond the documented
plugin API, so the supported Documenter version is pinned tightly in the
package's compat; expect breakage on untested Documenter releases.
