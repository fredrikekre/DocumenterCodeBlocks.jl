```@meta
CurrentModule = DocumenterCodeBlocks
```

# [Reference links](@id references)

Identifiers in code blocks that name a **documented object** become links to
the docstring — the code-block equivalent of Documenter's `@ref`. Resolution
uses the same machinery and the page's `CurrentModule` meta, so a code block
and an `@ref` link always agree on the target.

```julia
function demo(m::MyType)
    t = MyType(3)
    s = add_numbers(t.x, m.x)
    greet()
    return undocumented_helper(s)
end
```

Hover (or click) `MyType`, `add_numbers`, and `greet` above — and note that
`undocumented_helper` stays plain text: names that don't resolve are left
alone, silently.

Links attach to **call callees** (`add_numbers(...)`), **type positions**
(`m::MyType`), and plain **value mentions** — a documented name used as a
function argument, on the right of `=`, in a condition, and so on, like
`zero(MyType)` or a documented constant. What never links is a **binding**:
a name to the left of `=`, a function parameter, a loop variable — there the
name is not a use of the documented object (in the block above, the parameter
`m` binds and stays plain):

```julia
a = foo(1)      # links the foo(a) docstring
b = foo(1, 2)   # links the foo(a, b) docstring
c = foo         # value mention → links, listing both methods
d = DocumenterCodeBlocks.foo(1)   # qualified call
foo = c         # binding (left of =) → no link
```

As the block above shows, resolution is **arity-aware**: a call with `n`
positional arguments links to the method documented with `n` arguments,
not just to the first documented method. Qualified names resolve as a
whole, but the link attaches to the name itself — the module qualifier
and dot stay outside.

**Macro calls** link on their name. No syntactic vouching is needed there:
unlike a bare identifier, a macro name can only ever mean the macro.

```julia
@twice greet()                       # unqualified macro name
DocumenterCodeBlocks.@twice greet()  # qualified name
s = w"hello"                         # string macro
```

Code blocks inside docstrings get reference links too, with one exception:
a reference that resolves back to the enclosing docstring itself is left
unlinked — the reader is already looking at the target. A call whose arity
resolves to a *different* documented method still links, so an example in
[`foo(a, b)`](@ref)'s docstring that calls `foo(1)` links to [`foo(a)`](@ref).

# [Hover tooltips](@id tooltips)

Every reference link has a doxygen-style hover tooltip showing the target's
signature and the first sentence of its docstring. Tooltips are embedded in
the page at build time and work offline.

When a reference is **ambiguous** — several documented methods match — the
tooltip lists all candidate signatures instead; hovering an entry previews
its documentation and clicking navigates to it:

```julia
foo(args...)       # splat: positional count unknown → both methods listed
q = qux(1)         # same arity as qux("…") → both typed signatures listed
y = add_numbers(1, 2)  # single documented method → plain tooltip
```

## Arity pruning

Candidate lists only show methods that can actually take the call's argument
count. `measure` has six documented methods:

```julia
m = measure(args...)               # pure splat → all six methods listed
ml = measure(1, args...)           # at least 1 argument → the 0-argument method drops out
m1 = measure(1)                    # arity 1 → only the three 1-argument methods
m2 = measure(1, 2)                 # untyped (x, y) → exact match, single tooltip
```

## Aggregated docstrings

A bare `@docs` entry aggregates all of a function's docstrings under one
anchor. Tooltips are **arity-matched** within the aggregate: a call site with
a known argument count shows only the matching method's signature and
summary, while an unknown count shows all signature headers:

```julia
c2 = combine(1, 2)      # arity 2 → only combine(a, b) shown
c3 = combine(1, 2, 3)   # arity 3 → only combine(a, b, c) shown
cs = combine(args...)   # unknown arity → both signature headers shown
```

## Long signatures

Tooltips render multi-line signature headers verbatim and size to fit:

```julia
p = process(rand(3))               # arity prunes to the vector method
P = process(rand(3, 3), ones(3))   # arity 2 → the multi-line matrix signature
t = transform([1, 2, 3], sqrt; rev = true)
```

## Configuration

- `reference_links = false` turns linking off entirely,
- `popups = false` keeps the links but disables the tooltips.

Both are keyword arguments of [`CodeBlocks`](@ref).
