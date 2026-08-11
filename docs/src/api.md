```@meta
CurrentModule = DocumenterCodeBlocks
```

# API reference

The plugin's public API is a single type, passed to
`makedocs(plugins = [CodeBlocks()])`:

```@docs
CodeBlocks
```

## Demo API

The functions below are **not part of the package** — they exist only while
this documentation builds (evaluated into the module by `docs/make.jl`) so
that the manual can demonstrate [reference links and tooltips](@ref
references) against real docstrings. They also show off how docstrings
themselves are rendered: signature headers are highlighted but not numbered
or linked, while example blocks inside docstrings get the full treatment.

```@docs
greet
add_numbers
MyType
foo(a)
foo(a, b)
qux(x::Int)
qux(x::String)
transform
measure(x::Int)
measure(x::Float64)
measure(x::String)
measure(x, y)
measure(x, y, z)
measure()
combine
process(data::AbstractMatrix, weights::AbstractVector)
process(data::AbstractVector)
@twice
@w_str
```
