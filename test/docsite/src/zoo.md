# Code block zoo

```@meta
CurrentModule = DocumenterCodeBlocks
```

A collection of Julia code blocks covering the cases the line-numbers plugin
must handle.

## One-liner

A single-line block. With the default `min_lines = 1` it gets a gutter too
(a single line number), plus the id + permalink every block gets.

```julia
add_numbers(1, 2)
```

## Medium block

A handful of lines — the common case.

```julia
function assemble_element!(Ke, fe, cellvalues)
    n_basefuncs = getnbasefunctions(cellvalues)
    for q_point in 1:getnquadpoints(cellvalues)
        dΩ = getdetJdV(cellvalues, q_point)
        for i in 1:n_basefuncs
            δu = shape_value(cellvalues, q_point, i)
            fe[i] += δu * dΩ
        end
    end
    return Ke, fe
end
```

## Wide line

A multi-line block with one very long line that forces horizontal scrolling —
exercises the sticky gutter and the gap mask *while numbered*.

```julia
function process(data)
    result = some_function_with_a_very_long_name(first_argument, second_argument, third_argument, fourth_argument, fifth_argument, sixth_argument, seventh_argument)
    return result
end
```

## Multiline string

A triple-quoted string spanning several lines. The highlighted string token
crosses newlines — the hard case for the line-splitting algorithm.

```julia
const MESSAGE = """
    This is a multiline string.
    It spans several lines,
    and the string token crosses each newline boundary.
    """
println(MESSAGE)
```

## Plain block with a `# output` line

A plain `julia` block (NOT a `jldoctest`) that happens to contain a `# output`
comment. It must be highlighted normally — the `# output` split only applies to
real doctests, so `foo` below should still link and `y` should be highlighted.

```julia
x = foo(1)
# output
y = add_numbers(x, 2)
```

## Multiline comment

A `#= ... =#` block comment spanning several lines — another token that crosses
newlines.

```julia
#=
This is a block comment.
It also spans several lines.
Highlighters emit a single comment token across all of them.
=#
x = 42
```
