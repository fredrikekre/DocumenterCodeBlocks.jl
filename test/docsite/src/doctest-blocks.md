```@meta
CurrentModule = DocumenterCodeBlocks
DocTestSetup = :(import DocumenterCodeBlocks: greet, add_numbers, MyType, foo)
```

# Doctest & output blocks

A showcase of how the plugin renders the different code-block flavours, so the
`# output` handling can be compared side by side. The rule mirrors Documenter:
only a `jldoctest`-fenced block is a doctest, and it is script-style (split on a
lone `# output`) only when it has no `julia> ` prompt.

## 1. Plain `julia` block with `# output`

A plain `julia` block (**not** a doctest) that happens to contain a
`# output` line. It is **not** split — the whole block is highlighted, `# output`
is just a comment, and `foo`/`add_numbers` link:

```julia
x = foo(1)
# output
y = add_numbers(x, 2)
```

## 2. `jldoctest`, script-style

A `jldoctest` block with `# output` (no prompt). The input is highlighted and
linked; the `# output` marker and the result are program output → left plain:

```jldoctest
add_numbers(2, 3)

# output

5
```

## 3. Script-style, multi-statement input

Only the input above `# output` is treated as code:

```jldoctest
a = foo(5)
b = add_numbers(a, 10)
b * 2

# output

30
```

## 4. Script-style, output containing a documented name

The output mentions `foo` and `add_numbers`, but because it is program output it
stays plain — no spurious links, no highlighting:

```jldoctest
println("foo and add_numbers are functions")

# output

foo and add_numbers are functions
```

## 5. `jldoctest`, REPL-style

A `jldoctest` block with `julia> ` prompts renders as a REPL transcript:
prompts in green, inputs highlighted and linked, outputs plain:

```jldoctest
julia> add_numbers(2, 3)
5

julia> foo(10, 20)
30
```

## 6. `jldoctest; output = false`

With `output = false`, Documenter strips the output entirely, so only the input
remains — highlighted as a normal block:

```jldoctest; output = false
result = add_numbers(1, 2)

# output

3
```
