# Skip cases

Blocks that the plugin must treat specially (or not touch at all).

## julia-repl

A REPL transcript: prompts and input are highlighted (input gets reference
links), output is left plain — and with the default `repl_line_numbers = true`
the transcript gets a line-number gutter like any other block.

```julia-repl
julia> add_numbers(1, 2)
3

julia> greet()
Hello World!
```

## @example output

An executed example. The input block is a normal Julia block, but the **output**
block (`pre.documenter-example-output`) must be excluded.

```@example
using DocumenterCodeBlocks
DocumenterCodeBlocks.add_numbers(40, 2)
```

## nohighlight

A plain block with no language — must be left alone.

```nohighlight
this is not julia
just some plain text
```
