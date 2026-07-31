```@meta
CurrentModule = DocumenterCodeBlocks
DocTestSetup = :(import DocumenterCodeBlocks: add_numbers)
```

# [Syntax highlighting](@id highlighting)

Julia code is highlighted **at build time** by parsing each block with
[JuliaSyntax.jl](https://github.com/JuliaLang/JuliaSyntax.jl) — the same
parser Julia itself uses. Pages ship with the highlighting baked into the
HTML, so they render fully styled immediately, and classification always
agrees with the actual language grammar.

A plain `julia` block:

```julia
function mean_positive(xs::AbstractVector{<:Real})
    total, n = 0.0, 0
    for x in xs
        x > 0 || continue
        total += x
        n += 1
    end
    return n == 0 ? nothing : total / n
end
```

Because classification comes from a real parse tree, context-sensitive cases
come out right: callees get the function-call color, the right-hand side of
`::` and curly parameters get the type color, `:answer` is a symbol while
`quote` blocks are not, and string interiors, escapes, and multi-line
constructs never confuse the tokenizer:

```julia
config = Dict(
    :tolerance => 1e-8,
    :message => "multi-line strings?\nNo problem — even with \"quotes\".",
)
T = eltype(Vector{Float64})
```

## REPL transcripts

`julia-repl` blocks are highlighted too: prompts are marked, the input
expressions get full highlighting (and [reference links](@ref references)),
and output is left plain. Executed `@repl` blocks are rebuilt into the same
transcript form (their ANSI-colored output is kept as-is). Multi-line input
is handled by parsing until the expression is complete:

```julia-repl
julia> function double(x)
           2x
       end
double (generic function with 1 method)

julia> double(21)
42
```

## Doctests

`jldoctest` blocks work the same way. Script-style doctests split on the
`# output` marker exactly like Documenter does — the input is highlighted,
the output is not:

```jldoctest
x = add_numbers(1, 2)
println("x = ", x)

# output

x = 3
```

Blocks in other languages (and `@example` output, `nohighlight`, …) are left
untouched. The `languages` option of [`CodeBlocks`](@ref) controls which
block languages are processed.

## Parse tolerance

Highlighting is best-effort on invalid code: JuliaSyntax parses with error
recovery, so partially-broken snippets (work-in-progress examples,
docstring-style pseudo-signatures like `f(x[, y])`) still get sensible
colors instead of falling back to plain text.
