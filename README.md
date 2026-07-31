# DocumenterCodeBlocks.jl

[![Documentation](https://img.shields.io/badge/docs-latest%20release-blue.svg)](https://fredrikekre.github.io/DocumenterCodeBlocks.jl/)
[![CI](https://github.com/fredrikekre/DocumenterCodeBlocks.jl/actions/workflows/Test.yml/badge.svg?event=push)](https://github.com/fredrikekre/DocumenterCodeBlocks.jl/actions/workflows/Test.yml)
[![Codecov](https://codecov.io/github/fredrikekre/DocumenterCodeBlocks.jl/graph/badge.svg)](https://codecov.io/github/fredrikekre/DocumenterCodeBlocks.jl)
[![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl)

Enhanced code blocks for [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl):

- **Line numbers and linkable lines**, GitHub style: every block gets a permalink, and
  gutter click/shift-click/drag selects lines and puts a stable `#c-…-L3-L7` fragment in the
  URL.
- **Reference links**: identifiers in code blocks that name a documented object link to its
  docstring — call-arity aware, so `foo(1, 2)` links to the `foo(a, b)` method
  documentation.
- **Hover tooltips** (doxygen style) on every reference link: the target's signature and a
  one-line summary, embedded at build time. Ambiguous references show the candidate-method
  list instead.
- **Syntax highlighting** of Julia code blocks at build time with
  [JuliaSyntax.jl](https://github.com/JuliaLang/JuliaSyntax.jl) instead of highlight.js.
  Works for `julia`, `julia-repl`, `jldoctest`, and executed `@repl` blocks alike.
- **Docstring-quality warnings** that nudge toward tooltip-friendly docstrings (leading
  signature block, short first sentence).

Reference links and hover tooltips (ending with the candidate-method list for an
ambiguous splatted call):

![Demo of reference links and hover tooltips](https://global.discourse-cdn.com/julialang/original/3X/1/a/1a2cae96b243ca00d79bf77c06257cf31b23e5f6.gif)

Line selection with the permalink fragment updating in the URL:

![Demo of line numbers and line selection](https://global.discourse-cdn.com/julialang/original/3X/8/0/80dc3d791d58b0f0d7920cd9cbcab2bcf006573c.gif)

Try it live in the [documentation](https://fredrikekre.github.io/DocumenterCodeBlocks.jl/) —
every code block there is rendered by the plugin.

## Usage

To use the plugin, add the `CodeBlocks()` plugin to your `Documenter.makedocs` call:

```julia
using Documenter, DocumenterCodeBlocks

makedocs(
    # ...
    plugins = [CodeBlocks()],
)
```

The plugin is configurable with various keyword arguments, see the documentation of
`CodeBlocks`.

## Status

The plugin builds on Documenter internals beyond the documented plugin API, so updates
to Documenter might require updates to this plugin.

## License

MIT, see [LICENSE](LICENSE).
