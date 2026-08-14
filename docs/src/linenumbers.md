```@meta
CurrentModule = DocumenterCodeBlocks
```

# [Line numbers and linkable lines](@id linenumbers)

Every processed code block gets a line-number gutter and a stable id, GitHub
style. Try it on the block below:

- **click** a line number to select that line,
- **shift-click** (or **drag** along the gutter) to select a range,
- click the **link button** (top right of the block) to **copy the link** —
  to the current line selection if you have one in that block, else to the
  whole block; the icon flashes a checkmark to confirm,
- click anywhere outside the block to **deselect**.

The selection is reflected in the URL fragment (`#c-1a2b3c4d-L3-L7`), so a
copied link takes a reader to exactly these lines. The link button is a real
anchor, so the browser's usual affordances (right-click → *Copy Link*,
middle-click → new tab) work too. Block ids are content-addressed: they only
change when the code itself changes, not when the block moves around on the
page.

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

## Continued numbering

By default every block numbers from 1. A page can instead carry **one running
line counter** across its code blocks — tutorial style — by placing an
`@codeblocks` options block:

````markdown
```@codeblocks
line_counter = :continue
```
````

Like `@meta`, the setting applies from its position to the end of the page,
or until another `@codeblocks` block flips it back to `:restart` (the
default). All processed blocks participate — `julia`, `julia-repl`, and
executed `@repl` blocks — and line permalinks use the displayed numbers, so
a copied `#…-L12` link keeps meaning the line the reader saw. The two blocks
below share one counter:

```@codeblocks
line_counter = :continue
```

```julia
grid = [Point(float(i), float(j)) for i in 1:3, j in 1:3]
origin = Point(0.0, 0.0)
```

```julia
nearest = closest(vec(grid), origin)
r2 = norm2(nearest)
```

```@codeblocks
line_counter = :restart
```

A third mode, `line_counter = :named`, keeps one counter **per named
series**: blocks that share a name — `@example tutorial`, `@repl tutorial`,
`jldoctest tutorial`, or a plain fence with a second token like
```` ```julia tutorial ```` — continue each other (across block kinds and
across unrelated blocks in between), while unnamed blocks restart. This
pairs naturally with Documenter's named `@example`/`@repl` sandboxes, where
same-named blocks already share one session:

```@codeblocks
line_counter = :named
```

```@example numbering-demo
total = 1 + 2
nothing # hide
```

An unnamed block between the two restarts at 1, but the series picks up
where it left off:

```@example numbering-demo
total += 3
nothing # hide
```

```@codeblocks
line_counter = :restart
```

Blocks inside docstrings are their own page: they always start at 1 and
never advance any counter.

## Configuration

All knobs are keyword arguments of [`CodeBlocks`](@ref):

- `line_numbers = false` disables the gutter (blocks are still highlighted
  and linked, and keep their id + permalink),
- `repl_line_numbers = false` disables the gutter for `julia-repl` blocks
  only,
- `line_counter` sets the site-wide default line-counter mode (`:restart`,
  `:continue`, or `:named`) — `@codeblocks` blocks override it per page,
  positionally,
- `min_lines` sets the minimum block length that gets a gutter — the default
  `1` numbers everything, including one-liners:

```julia
answer = add_numbers(40, 2)
```

The signature header of a rendered docstring is deliberately **not** numbered
— it is a header, not example code (its argument and return types do get
reference links, though — see [Reference links](@ref references)).
