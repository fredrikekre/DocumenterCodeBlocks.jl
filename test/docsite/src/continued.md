```@meta
CurrentModule = DocumenterCodeBlocks
```

# Continued numbering & positional meta

This page exercises the `@codeblocks` options block and positional metadata:
one running line counter across blocks (`line_counter = :continue`), flipping
back to `:restart` mid-page, an `@meta CurrentModule` switch that applies
from its position on, and a `@docs` entry proving docstrings are their own
page.

```@codeblocks
line_counter = :continue
```

The first block numbers 1–4 as usual (`greet` and `add_numbers` resolve in
`DocumenterCodeBlocks`, the page's `CurrentModule` here; `inner_fn` must NOT
resolve yet):

```julia
greet()
x = add_numbers(1, 2)
y = inner_fn  # not in scope here: no link
z = x + 1
```

A REPL transcript continues at line 5:

```julia-repl
julia> add_numbers(20, 22)
42
```

An executed `@repl` block continues at line 7:

```@repl
import DocumenterCodeBlocks
DocumenterCodeBlocks.add_numbers(2, 3)
```

A one-liner also continues (line 11) and advances the counter:

```julia
greet()
```

## Docstrings are their own page

The docstring below sits in the middle of the continued sequence. Its example
block starts at 1 (no `data-ln-start`) and does not advance the page counter:

```@docs
DocumenterCodeBlocks.stepwise
```

The next page block therefore continues at line 12:

```julia
a = greet()
b = add_numbers(1, 1)
```

## Switching the module mid-page

```@meta
CurrentModule = DocumenterCodeBlocks.DemoInner
```

From here on unqualified names resolve in `DemoInner` — `inner_fn` links now,
while `add_numbers` (defined in the parent module) no longer resolves
unqualified. Numbering still continues (line 14):

```julia
v = inner_fn(21)
w = inner_helper(v)
u = add_numbers  # not in scope here: no link
```

## Back to restarting

```@codeblocks
line_counter = :restart
```

After flipping back, this block starts at 1 again:

```julia
p = inner_fn(1)
q = inner_helper(p)
```

A longer restart block (exercises gutter selection on this page too):

```julia
function walkthrough(v)
    s = zero(eltype(v))
    for x in v
        s = inner_fn(s) + x
    end
    if isempty(v)
        s = -1
    end
    return s
end
```

## Named series

```@codeblocks
line_counter = :named
```

Under `line_counter = :named` each **named series** carries its own counter,
mixing block kinds; unnamed blocks restart. The `@example series-a` pair
below continues 1–2 → 3–4 across the unrelated blocks between them, and the
named `jldoctest` pair continues 1–2 → 3–4 independently:

```@example series-a
a1 = 1 + 1
a2 = a1 + 1
nothing # hide
```

An unnamed block in named mode restarts (and touches no series):

```julia
t = inner_helper(3)
```

A different name is a different series (starts at 1):

```@example series-b
b1 = 10
nothing # hide
```

```@example series-a
a3 = a2 + 1
nothing # hide
```

```jldoctest counter-demo
julia> x = 20 + 1
21
```

```jldoctest counter-demo
julia> x + 21
42
```

## DemoInner API

The docstrings for the `DemoInner` demo module (referenced unqualified above,
under the switched `CurrentModule`):

```@docs
inner_fn
inner_helper
```
