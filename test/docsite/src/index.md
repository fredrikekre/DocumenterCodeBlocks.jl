```@meta
CurrentModule = DocumenterCodeBlocks
```

# DocumenterCodeBlocks testbed

The development **testbed** for DocumenterCodeBlocks.jl (this is *not* the user
documentation — see `docs/`): the pages below contain a "zoo" of code blocks
covering every case the plugin must handle (and every case it must leave
alone). `test/runtests.jl` and the Playwright suites assert against this
site's build output.

- [Code block zoo](@ref) — one-liners, medium/wide blocks, multiline
  strings/comments.
- [Big block](@ref) — a ≥100-line block (exercises the 3-digit gutter).
- [Skip cases](@ref) — `julia-repl`, `@example` output, and `nohighlight`
  blocks that must be left untouched.
- [Reference links](@ref) — identifiers that resolve to docstrings.

## API

```@docs
DocumenterCodeBlocks.CodeBlocks
DocumenterCodeBlocks.greet
DocumenterCodeBlocks.add_numbers
DocumenterCodeBlocks.MyType
DocumenterCodeBlocks.foo(a)
DocumenterCodeBlocks.foo(a, b)
DocumenterCodeBlocks.bar
DocumenterCodeBlocks.baz
DocumenterCodeBlocks.qux(x::Int)
DocumenterCodeBlocks.qux(x::String)
DocumenterCodeBlocks.transform
DocumenterCodeBlocks.neg(x::Int)
DocumenterCodeBlocks.measure(x::Int)
DocumenterCodeBlocks.measure(x::Float64)
DocumenterCodeBlocks.measure(x::String)
DocumenterCodeBlocks.measure(x, y)
DocumenterCodeBlocks.measure(x, y, z)
DocumenterCodeBlocks.measure()
DocumenterCodeBlocks.combine
DocumenterCodeBlocks.wordy
DocumenterCodeBlocks.fit(x::AbstractVector, y::AbstractVector)
DocumenterCodeBlocks.fit(X::AbstractMatrix, w::AbstractVector)
DocumenterCodeBlocks.process(data::AbstractMatrix, weights::AbstractVector)
DocumenterCodeBlocks.process(data::AbstractVector)
DocumenterCodeBlocks.@twice
DocumenterCodeBlocks.@w_str
```
