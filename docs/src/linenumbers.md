```@meta
CurrentModule = DocumenterCodeBlocks
```

# [Line numbers and linkable lines](@id linenumbers)

Every processed code block gets a line-number gutter and a stable id, GitHub
style. Try it on the block below:

- **click** a line number to select that line,
- **shift-click** (or **drag** along the gutter) to select a range,
- click the **link button** (top right of the block) to select the whole block,
- click anywhere outside the block to **deselect**.

The selection is reflected in the URL fragment (`#c-1a2b3c4d-L3-L7`), so you
can copy the address and link a reader to exactly these lines. Block ids are
content-addressed: they only change when the code itself changes, not when
the block moves around on the page.

```julia
struct Point{T <: Real}
    x::T
    y::T
end

norm2(p::Point) = p.x^2 + p.y^2

function closest(points::AbstractVector{<:Point}, target::Point)
    _, i = findmin(p -> norm2(Point(p.x - target.x, p.y - target.y)), points)
    return points[i]
end
```

Line numbers live in the gutter's CSS, not in the text — selecting and
copying code never picks up the digits, and horizontal scrolling keeps the
gutter pinned.

## REPL transcripts

Transcripts are numbered too (all lines count, including output), which makes
REPL sessions linkable line by line:

```julia-repl
julia> p = Point(3.0, 4.0)
Point{Float64}(3.0, 4.0)

julia> norm2(p)
25.0
```

## Configuration

All knobs are keyword arguments of [`CodeBlocks`](@ref):

- `line_numbers = false` disables the gutter (blocks are still highlighted
  and linked, and keep their id + permalink),
- `repl_line_numbers = false` disables the gutter for `julia-repl` blocks
  only,
- `min_lines` sets the minimum block length that gets a gutter — the default
  `1` numbers everything, including one-liners:

```julia
answer = add_numbers(40, 2)
```

The signature header of a rendered docstring is deliberately **not** numbered
(nor linked) — it is a header, not example code.
