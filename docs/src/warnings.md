# [Docstring warnings](@id warnings)

The [tooltips](@ref tooltips) extract two things from every referenced
docstring: the **signature** (the docstring's first code block) and a
**brief** (the first sentence of its first prose paragraph). When
a docstring doesn't provide them, the tooltip degrades gracefully — and the
build emits a warning telling the author what to fix. The aim is to nudge
docstrings toward a shape that works well in tooltips and reads well
everywhere else, too.

The warnings are prefixed `CodeBlocks: `, fire **once per problem** per
build, and only for docstrings that some code block actually references.

## No signature block

The tooltip falls back to a signature synthesized from the method object:

```nohighlight
┌ Warning: CodeBlocks: the docstring for `MyPackage.frob (Tuple{Int64})` has no signature
│ code block; tooltips fall back to the synthesized signature `frob(::Int64)`. Give it
│ one, either leading (the Julia convention) or directly after the summary paragraph:
│     """
│         frob(::Int64)
│
│     ...
│     """
```

## No prose paragraph

The tooltip shows only the signature:

```nohighlight
┌ Warning: CodeBlocks: the docstring for `MyPackage.frob` has no prose paragraph;
│ tooltips show only the signature. Add a short first sentence describing what it does.
```

## Overlong first sentence

The brief is clipped at 200 characters if no sentence boundary is found:

```nohighlight
┌ Warning: CodeBlocks: the first paragraph of the docstring for `MyPackage.frob` has no
│ sentence boundary within 200 characters; the tooltip brief is truncated mid-sentence.
│ Start the docstring with one short summary sentence.
```

## Arity without a documented method

A code block calls a documented function with an argument count no documented
method accepts — often a sign that a method is missing its docstring, or that
the example is stale:

```nohighlight
┌ Warning: CodeBlocks: no documented method of `MyPackage.frob` takes 4 arguments, but a
│ code block calls it that way; the tooltip lists all documented methods. Is a method
│ missing its docstring?
```

(Documenter itself resolves the equivalent `[`frob(a, b, c, d)`](@ref)`
silently to the first documented method — the plugin links the same way, it
just tells you about it.)
