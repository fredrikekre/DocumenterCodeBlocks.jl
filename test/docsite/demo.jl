# Demo API for the DocumenterCodeBlocks test docsite.
#
# These documented functions exist ONLY while building the test docsite: the
# file is evaluated INTO the DocumenterCodeBlocks module by test/docsite/make.jl
# (`Base.include(DocumenterCodeBlocks, ...)`), so anchors and tooltips read
# `DocumenterCodeBlocks.foo` exactly as they would for native API — but nothing
# here ships with the package. The set deliberately includes DEGRADED
# docstrings (no signature block, no prose, an overlong first sentence, a
# method-arity gap) to exercise the tooltip fallbacks and the `CodeBlocks: `
# build warnings.

# ---------------------------------------------------------------------------
# Testbed demo API — documented objects the docs/ pages reference so we can
# exercise reference links. (Not part of the plugin's public surface.)
# ---------------------------------------------------------------------------

"""
    greet()

Print a friendly greeting to standard output. A minimal documented function for
exercising reference links from code blocks.

# Examples

A `julia-repl` block inside a docstring:

```julia-repl
julia> greet()
Hello World!
```

A script-style `jldoctest` whose output is NOT valid Julia (and contains the
documented name `foo`) — to see how the highlighter copes:

```jldoctest
println("foo bar baz")

# output

foo bar baz
```
"""
greet() = print("Hello World!")

"""
    add_numbers(a, b)

Return the sum of `a` and `b`. A trivial documented function used in the docs
testbed to verify that identifiers in code blocks link to their docstrings.

# Examples

A plain `julia` block (gets highlighting, line numbers, and reference links —
note `foo` links to its docstring):

```julia
x = add_numbers(1, 2)
y = add_numbers(x, foo(10))
```

A `jldoctest` block (executed and checked by Documenter):

```jldoctest
julia> add_numbers(2, 3)
5

julia> add_numbers(add_numbers(1, 2), 3)
6
```

A `julia-repl` block with a multi-line input (the whole `function … end`
definition is one input, highlighted together):

```julia-repl
julia> function describe(a, b)
           s = add_numbers(a, b)
           return "sum is \$s"
       end
describe (generic function with 1 method)

julia> describe(2, 3)
"sum is 5"
```
"""
add_numbers(a, b) = a + b

"""
    MyType

A documented type used to check that type identifiers in code blocks resolve to
their docstring anchors.

# Examples

```jldoctest
julia> MyType(3)
MyType(3)

julia> MyType(3).x
3
```
"""
struct MyType
    x::Int
end

"""
    foo(a)

The one-argument method of `foo`. Has its own docstring, separate from
[`foo(a, b)`](@ref), to test how links resolve for functions with multiple
documented methods.

# Examples

A script-style `jldoctest` (code, then `# output`, then the expected result):

```jldoctest
values = [foo(i) for i in 1:3]
total = add_numbers(values[1], values[3])

# output

4
```
"""
foo(a) = a

"""
    foo(a, b)

The two-argument method of `foo`, with its own docstring separate from
[`foo(a)`](@ref).

# Examples

```jldoctest
julia> foo(10, 20)
30
```
"""
foo(a, b) = a + b

"""
Increment `a` by one. This docstring intentionally has **no** leading signature
code block, so the hover tooltip's signature must be synthesized from the
documented method itself.
"""
bar(a) = a + 1

"""
    qux(x::Int)

Double an integer. Same-arity sibling of [`qux(x::String)`](@ref) — the two
methods differ only in argument *type*, which a call site like `qux(1)` cannot
disambiguate (we only extract arity), so references to `qux` list both.
"""
qux(x::Int) = 2x

"""
    qux(x::String)

Repeat a string. See [`qux(x::Int)`](@ref) for the same-arity integer method.
"""
qux(x::String) = x^2

"""
    transform(v::AbstractVector{T}, f::Function = identity; rev::Bool = false) where {T}

Apply `f` to each element of `v`, optionally reversing the result. The
signature exercises type annotations, a parametric container, a default
argument, a keyword argument, and a `where` clause in the hover tooltip.
"""
function transform(v::AbstractVector, f::Function = identity; rev::Bool = false)
    out = map(f, v)
    return rev ? reverse!(out) : out
end

"""
Negate an integer. Like [`bar`](@ref) this docstring has no signature code
block, but the documented method is *typed*, so the synthesized tooltip
signature shows the argument type.
"""
neg(x::Int) = -x

"""
    measure(x::Int)

Measure an integer. One of **six** documented methods of `measure`, together
stress-testing long disambiguation lists.
"""
measure(x::Int) = x

"""
    measure(x::Float64)

Measure a float, rounding to the nearest integer.
"""
measure(x::Float64) = round(Int, x)

"""
    measure(x::String)

Measure a string by its length.
"""
measure(x::String) = length(x)

"""
    measure(x, y)

Measure two things together.
"""
measure(x, y) = measure(x) + measure(y)

"""
    measure(x, y, z; scale::Real = 1)

Measure three things, scaled.
"""
measure(x, y, z; scale::Real = 1) = scale * (measure(x) + measure(y) + measure(z))

"""
    measure()

Measure nothing at all. The 0-argument method: excluded from disambiguation
lists whenever the call site guarantees at least one positional argument, even
via a splat like `measure(x, rest...)`.
"""
measure() = 0

"""
    process(data::AbstractMatrix{<:Real}, weights::AbstractVector{<:Real};
            normalize::Bool = true, atol::Real = 1e-8,
            callback::Union{Function, Nothing} = nothing) -> AbstractMatrix

Process a data matrix with per-column `weights`. The signature block spans
several lines, stress-testing the tooltip layout for long headers.
"""
process(data::AbstractMatrix, weights::AbstractVector; kwargs...) = data

"""
    process(data::AbstractVector{<:Real}; normalize::Bool = true, atol::Real = 1e-8)

Process a single data vector. Long single-line signature header, and the
same-name sibling of the matrix method above.
"""
process(data::AbstractVector; kwargs...) = data

"""
    baz(a)
"""
baz(a) = a   # docstring with no prose: tooltip gets a signature but no brief

"""
    wordy(x)

Return `x` after an exceptionally long-winded description that keeps rambling
on and on without ever arriving at a sentence boundary because it keeps adding
qualifiers and clauses and parentheticals and yet more clauses far beyond any
reasonable summary length before finally stopping.
"""
wordy(x) = x   # >200 chars before the first sentence boundary → clipped brief + warning

"""
    combine(a, b)

Combine two things. `combine` is included in the docs with a bare
`@docs DocumenterCodeBlocks.combine` entry (no signature), so this docstring
and the three-argument one render **aggregated inside one docstring
`<details>`** — but each docstring still gets its own `<section><div>`, so
both signature headers receive the header treatment (highlight only).
"""
combine(a, b) = (a, b)

"""
    combine(a, b, c)

Combine three things. The second docstring of the aggregated `combine` entry;
its signature header must be stripped of gutter/links just like the first.
"""
combine(a, b, c) = (a, b, c)

"""
    fit(
        x::AbstractVector,
        y::AbstractVector,
    )

Fit a line through points. The signature block is deliberately spread over
multiple lines (with a trailing comma): the tooltip shows it verbatim, but
disambiguation-list labels collapse it to one line.
"""
fit(x::AbstractVector, y::AbstractVector) = nothing

"""
    fit(
        X::AbstractMatrix,
        w::AbstractVector,
    )

Fit a plane through weighted samples. Same arity as the vector method, so
every `fit` call site is ambiguous and both multiline headers appear as
collapsed one-line labels in the candidate list.
"""
fit(X::AbstractMatrix, w::AbstractVector) = nothing
