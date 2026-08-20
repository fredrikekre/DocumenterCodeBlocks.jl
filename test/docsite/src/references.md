# Reference links

```@meta
CurrentModule = DocumenterCodeBlocks
```

With `CurrentModule = DocumenterCodeBlocks`, unqualified names in a code block
should resolve to their docstrings (defined on the [home page](@ref "DocumenterCodeBlocks-testbed")).

This block uses documented names (`add_numbers`, `greet`, `MyType`) that the
plugin should turn into links to their docstring anchors, plus an undocumented
name (`undocumented_helper`) that must stay plain text. Call callees, type
annotations (like the `m::MyType` argument below), and plain value mentions
all link; names in binding positions — like the parameter `m` — do not (see
below).

```julia
function demo(m::MyType)
    t = MyType(3)
    s = add_numbers(t.x, m.x)
    greet()
    return undocumented_helper(s)
end
```

For comparison, the same names in markdown resolve with `@ref`:
[`add_numbers`](@ref), [`greet`](@ref), and [`MyType`](@ref).

## Macros

Macro names link like call callees do, whether written unqualified, qualified,
or as the prefix of a string-macro literal. An undocumented macro stays plain
text.

```julia
@twice greet()                       # unqualified macro name
DocumenterCodeBlocks.@twice greet()  # qualified name
@twice(add_numbers(1, 2))            # arguments keep their own links
s = w"hello"                         # string macro
@undocumented_macro 1                # not documented → plain text
```

## Multiple methods

`foo` has two documented methods, [`foo(a)`](@ref) and [`foo(a, b)`](@ref), each
with its own docstring. Call sites link arity-aware; a plain value mention of
`foo` links too (with the unknown-arity candidate list), but a **binding** of
the name — left of `=`, a parameter, a loop variable — is not a use and stays
unlinked.

```julia
a = foo(1)      # links the foo(a) docstring
b = foo(1, 2)   # links the foo(a, b) docstring
c = foo         # value mention → links (both methods listed)
d = DocumenterCodeBlocks.foo(1)   # qualified call: the link is on the name only
e = map(foo, [1, 2])              # passed as a value → links
foo = c         # binding position (left of =) → no link
```

## Hover popups

Doxygen-style tooltips: hovering **any** reference link shows the target's
signature and the first sentence of its docstring — embedded per page at build
time, nothing is fetched. When a reference is **ambiguous** —
like the splatted call below, where the positional count is unknown and two
documented methods match — the tooltip instead lists all candidate signatures;
hovering an entry shows its tip, clicking navigates to it.

```julia
foo(args...)       # splat: positional count unknown → disambiguation popup
x = foo(1)         # exact arity match → tooltip: signature + brief
y = add_numbers(1, 2)  # single documented method → tooltip: signature + brief
b = bar(1)         # docstring has no signature block → signature synthesized
z = baz(1)         # docstring has no prose → tooltip without a brief
w = wordy(1)       # first sentence >200 chars → brief truncated (build warning)
```

Each of the imperfect cases above also emits a `CodeBlocks: ` build warning
telling the docstring author what to fix.

The signature is the docstring's first code block and the brief its first
prose paragraph, whichever order the two appear in: `summarize` writes the
summary paragraph first and the signature block after it. In `sampled` the
only code block sits further down, under a heading — that one is an example,
so its tooltip signature is synthesized.

```julia
u = summarize(2)   # signature block after the summary paragraph
e = echoed(u)      # doctest after the summary paragraph → still an example
s = sampled(e)     # code block under a heading → synthesized signature
h = halved(s)      # named fence after the summary → still an example
```

## Type annotations

`qux` has two documented methods of the **same arity** that differ only in the
argument type — `qux(x::Int)` and `qux(x::String)`. A call site only reveals
the arity, never the types, so *every* reference to `qux` is ambiguous and
lists both typed signatures. `transform` puts a parametric container, default
argument, keyword argument, and `where` clause in the tooltip; `neg` has a
typed method but no signature block in its docstring, so the tooltip signature
is synthesized *with* the argument type.

```julia
q1 = qux(1)        # same arity as qux("…") → both typed signatures listed
q2 = qux("hi")     # ditto — we don't peek at literal argument types
t = transform([1, 2, 3], sqrt; rev = true)
n = neg(2)         # synthesized signature: neg(::Int64)
```

## Long signatures, many methods

`measure` has **six** documented methods (a 0-argument one, three typed
one-argument methods, plus untyped two- and three-argument ones). A pure-splat
call could mean any of them; a call site's arity prunes the list to the methods
that can actually take that many positional arguments — and a splat after some
fixed arguments still gives a *lower bound*, which rules out the 0-argument
method. `process` has two methods with **long** signature headers — the matrix
one spans multiple lines in its docstring — exercising tooltip width and
wrapping.

```julia
m = measure(args...)               # pure splat → all six methods listed
ml = measure(1, args...)           # at least 1 argument → the 0-argument method drops out
m1 = measure(1)                    # arity 1 → only the three 1-argument methods
m2 = measure(1, 2)                 # untyped (x, y) → exact match, single tooltip
p = process(rand(3))               # arity prunes to the vector method → its long tooltip
P = process(rand(3, 3), ones(3))   # arity 2 → the multi-line matrix signature
bad = measure(1, 2, 3, 4)          # no 4-argument method documented → build warning
```

## Aggregated and multiline docstrings

`combine` is documented as one **aggregated** entry (a bare `@docs` name), so
every reference resolves to the same docstring anchor — but the tooltip is
**arity-matched**: a call site with a known argument count shows only the
signature (and brief) of the matching method, while an unknown count (splat)
shows all signature headers. Both `fit` methods spell their signature over
**multiple lines** in the docstring; the tooltip shows them verbatim, while
the disambiguation list collapses each to a one-line label.

```julia
c2 = combine(1, 2)                 # aggregated docstring, arity 2 → only combine(a, b) shown
c3 = combine(1, 2, 3)              # same anchor, arity 3 → only combine(a, b, c) shown
cs = combine(args...)              # unknown arity → both signature headers shown
f = fit([1.0, 2.0], [3.0, 4.0])    # same-arity pair with multiline headers → collapsed labels
```
