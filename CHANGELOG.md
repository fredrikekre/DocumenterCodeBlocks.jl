# DocumenterCodeBlocks.jl changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.4.0] - 2026-08-20

### Added
 - The block permalink button now copies the link to the clipboard on click,
   confirmed by flashing the icon to a checkmark — matching the copy-code
   button next to it. With lines selected in that block the copied link
   targets the selection, otherwise the whole block. The button is now a
   real anchor (`<a href="#c-…">`), so right-click → *Copy Link* and
   middle-/ctrl-click open-in-new-tab work natively too. On insecure
   contexts without clipboard access the click degrades to the previous
   behavior (URL fragment only). ([#17])

### Fixed
 - Tooltip briefs no longer truncate the docstring's first sentence at
   mid-sentence periods. A `.`/`!`/`?` now only ends the sentence when the
   next word does not start with a lowercase letter (so `meas. outputs`,
   `sort! the vector` and `args... to` continue) and when it does not
   complete a known abbreviation such as `e.g.`, `i.e.`, `etc.` or `a.k.a.`.
   Punctuation inside inline code is never a sentence end (`Base.sort!`
   stays intact), while a code span starting the next word always is
   ("Sort `v` in place. `alg` controls …" cuts before `alg`). ([#16])

## [v1.3.0] - 2026-08-13

### Added
 - New `@codeblocks` block for page-local plugin options, applied
   positionally like `@meta`. The first option is `line_counter`:
   `:continue` carries one running line counter across the page's code
   blocks (tutorial style), and `:named` keeps one counter per named series
   (`@example name`, `@repl name`, `jldoctest name`, …) with unnamed blocks
   restarting — instead of the default `:restart` numbering from 1. The
   site-wide default mode is configurable with `CodeBlocks(line_counter = …)`.
   Line permalinks use the displayed numbers. Blocks inside docstrings are
   their own page: they always start at 1 and do not advance any counter.
   ([#14])
 - Reference resolution now follows `@meta CurrentModule` **positionally**,
   exactly like `@ref`: a mid-page module switch applies from its position
   on, and code blocks inside a docstring resolve in the docstring's own
   module. Previously the page-final state applied everywhere. ([#14])

## [v1.2.0] - 2026-08-12

### Added
 - Macro names in code blocks now link to their docstring, like function calls
   and type annotations already did. ([#8], [#10])
 - Identifiers used as plain *values* — function arguments (`zero(T)`),
   enum/constant mentions, the right-hand side of `=`, … — now link to their
   docstring like call callees and type annotations already did. Names in
   *binding* positions (left of `=`, function parameters, loop variables,
   `local`/`const` declarations, …) are not uses and stay unlinked. ([#9],
   [#12])
 - Docstring signature headers now link their argument and return types;
   the documented name itself and the parameter names stay plain. To keep the
   name unlinked also for same-arity siblings, self-reference suppression is
   now candidate-aware: a reference is left unlinked whenever the enclosing
   docstring is among its candidate targets, not only when it is the primary
   target. ([#11], [#13])
### Changed
 - Reference links on qualified names (`Foo.bar(...)`, `Foo.@bar`,
   `x::Foo.Bar`) now wrap only the name; the module qualifier and dot stay
   outside the link. ([#10])

## [v1.1.0] - 2026-08-02

### Changed
 - Reference-link underlines in code blocks are now soft dotted at rest and
   turn solid while the pointer is inside the code block, instead of
   full-strength dotted underlines everywhere. This addresses feedback that
   the underlines were visually distracting in call-heavy code. ([#6])

## [v1.0.1] - 2026-07-31

### Fixes
 - Executed `@repl` blocks, which were previously left untouched, are now processed like
   `julia-repl` fences (prompts, input highlighting, reference links, and line numbers) with
   ANSI-colored output preserved. ([#3], [#5])

## [v1.0.0] - 2026-07-31

First stable release of DocumenterCodeBlocks.jl — a Documenter.jl plugin
(`makedocs(plugins = [CodeBlocks()])`) that enhances Julia code blocks:

 - Line numbers and linkable lines, GitHub style: content-addressed block ids
   with permalinks, and gutter click/shift-click/drag line selection reflected
   in the URL fragment.
 - Reference links: identifiers in call/type position that name a documented
   object link to its docstring, resolved with `@ref` semantics and call-arity
   awareness (including splat lower bounds).
 - Doxygen-style hover tooltips on every reference link: signature and
   first-sentence summary, embedded per page at build time. Ambiguous
   references list the arity-pruned candidate methods; aggregated docstrings
   are arity-matched.
 - Build-time syntax highlighting with JuliaSyntax for `julia`, `julia-repl`,
   and `jldoctest` blocks — no highlight.js, node, or `prerender` needed.
 - Build warnings (prefixed `CodeBlocks: `) that nudge toward tooltip-friendly
   docstrings.

See [README.md](README.md) and the documentation for details.


<!-- Links generated by Changelog.jl -->

[v1.0.0]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/releases/tag/v1.0.0
[v1.0.1]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/releases/tag/v1.0.1
[v1.1.0]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/releases/tag/v1.1.0
[v1.2.0]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/releases/tag/v1.2.0
[v1.3.0]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/releases/tag/v1.3.0
[v1.4.0]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/releases/tag/v1.4.0
[#3]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/3
[#5]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/5
[#6]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/6
[#8]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/8
[#10]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/10
[#9]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/9
[#11]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/11
[#12]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/12
[#13]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/13
[#14]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/14
[#16]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/16
[#17]: https://github.com/fredrikekre/DocumenterCodeBlocks.jl/issues/17
