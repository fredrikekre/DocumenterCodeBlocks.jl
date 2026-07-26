# The JuliaSyntax highlighter (tree-based) with integrated reference links.
#
# A SINGLE recursive walk of the lossless GreenNode tree emits HTML directly.
# There is no annotation array and no overlap to resolve: the green-tree leaves
# tile the source exactly, so every byte is emitted by exactly one leaf. Context
# that a leaf can't see on its own — "I'm the callee of a call" → funcall, "I'm to
# the right of a `::`" → type — is passed *down* as an inherited `role`. Reference
# links attach to whole nodes (an identifier leaf, or a dotted-name subtree) and
# only in role-vouched positions (callees and type annotations); a node that
# resolves wraps its emitted children in an <a>.
#
# Multiline string/comment tokens keep their embedded newlines; `split_highlighted`
# then breaks the emitted HTML into per-line fragments (reopening spans/anchors).
#
# Classification mirrors a focused subset of the JuliaSyntaxHighlighting stdlib.

import JuliaSyntax
using JuliaSyntax: @K_str

const _JS = JuliaSyntax

# Face symbol -> CSS class.
const FACE_CLASS = Dict{Symbol, String}(
    :keyword => "julia-keyword",
    :comment => "julia-comment",
    :string => "julia-string",
    :number => "julia-number",
    :macro => "julia-macro",
    :operator => "julia-operator",
    :funcall => "julia-funcall",
    :type => "julia-type",
    :symbol => "julia-symbol",
)

const SINGLETONS = Set{Symbol}([:nothing, :missing, :Inf, :NaN, :undef])

function _escape_html(s::AbstractString)
    return replace(
        s,
        '&' => "&amp;", '<' => "&lt;", '>' => "&gt;", '"' => "&quot;", '\'' => "&#39;",
    )
end

_noderange(offset, node) = (offset + 1):(offset + Int(_JS.span(node)))
_text(cu, r) = String(cu[r])

# The face for a single leaf, given the role inherited from its context.
# Intrinsic faces (keyword/number/string/…) win; an unclassified, non-trivia token
# (a plain identifier, or a bracket inside a type) falls back to the inherited role.
# Note: bare type names in VALUE position (`zeros(Int, 3)`) deliberately stay
# plain — syntax alone can't tell a type from any other value there; type color
# comes only from type positions (`::` RHS, curly parameters).
function _leaf_face(k, role, name, trivia)
    _JS.is_keyword(k) && return :keyword
    # A quoted symbol (`:foo`) colors all its tokens, the leading `:` included
    # (the sigil is a trivia token; a symbol-quote node contains nothing else).
    role === :symbol && return :symbol
    k == K"Comment" && return :comment
    (
        k == K"String" || k == K"CmdString" || k == K"Char" || _JS.is_string_delim(k) ||
            k == K"`" || k == K"```"
    ) && return :string
    (k == K"Bool" || _JS.is_number(k)) && return :number
    (k == K"MacroName" || k == K"StringMacroName" || k == K"CmdMacroName" || k == K"@") && return :macro
    if k == K"Identifier"
        name in SINGLETONS && return :symbol
        # Word-operators (`*`, `<:`, `in`, `isa`, …) tokenize as Identifier.
        Base.isoperator(name) && return :operator
        return role === :none ? :none : role
    end
    _JS.is_operator(k) && return :operator
    # brackets/commas etc. inside a type region inherit the type color; never trivia.
    (role !== :none && !trivia) && return role
    return :none
end

function _emit_leaf(io, text, face, ref)
    esc = _escape_html(text)
    ref !== nothing && _print_ref_open(io, ref)
    if face === :none
        print(io, esc)
    else
        print(io, "<span class=\"", FACE_CLASS[face], "\">", esc, "</span>")
    end
    ref !== nothing && print(io, "</a>")
    return
end

# Open the <a> for a resolved reference (`ref` from resolve_reference). Ambiguous
# references (several candidate targets) additionally carry their candidate
# (label, href) pairs as a JSON array in `data-ref-targets`, consumed by
# ref-popup.js; tooltip bodies live in the per-page `.ref-tips` payload instead.
# A single target whose tip was arity-narrowed (aggregated docstring) points at
# its variant tip via `data-ref-tip` — the href alone would find the shared,
# un-narrowed payload.
function _print_ref_open(io, ref)
    print(io, "<a class=\"julia-ref\" href=\"", _escape_html(ref.href), "\"")
    if length(ref.targets) > 1
        print(io, " data-ref-targets=\"", _escape_html(_targets_json(ref.targets)), "\"")
    elseif (t = only(ref.targets)).tipkey != t.href
        print(io, " data-ref-tip=\"", _escape_html(t.tipkey), "\"")
    end
    print(io, ">")
    return
end

_json_str(s) = string('"', replace(s, '\\' => "\\\\", '"' => "\\\""), '"')
_targets_json(targets) =
    string("[", join(("[$(_json_str(t.label)),$(_json_str(t.href))]" for t in targets), ","), "]")

# A `.` node that is a plain dotted name (Foo.bar): only identifiers/dots/quotes.
function _is_dotted_name(node)
    for c in _JS.children(node)
        kc = _JS.kind(c)
        (kc == K"Identifier" || kc == K"." || kc == K"quote" || _JS.is_trivia(c)) || return false
    end
    return true
end

# A quoted symbol (`:foo`): exactly the `:` token followed by an identifier.
# (Excludes `quote … end` blocks and quoted expressions like `:(a + b)`.)
function _is_symbol_quote(node)
    cs = _JS.children(node)
    return cs !== nothing && length(cs) == 2 &&
        _JS.kind(cs[1]) == K":" && _JS.kind(cs[2]) == K"Identifier"
end

# Index (into children) of the last Identifier child, or 0.
function _last_ident_index(node)
    idx, i = 0, 0
    for c in _JS.children(node)
        i += 1
        _JS.kind(c) == K"Identifier" && (idx = i)
    end
    return idx
end

# Bracket/comma tokens that are not call arguments.
const _PUNCT = (K"(", K")", K"[", K"]", K"{", K"}", K",", K";")
# Call arity for link resolution is an exact `Int`, `nothing` (unknown), or a
# lower bound: `f(a, b...)` has at least 1 positional argument, which still
# rules out documented 0-argument methods even though the exact count is
# unknown (each splat contributes ≥ 0 arguments).
struct AtLeast
    n::Int
end
# Call-argument counting for arity-aware link resolution. Keyword arguments —
# a `parameters` node (`; kw=1`) or an `=` node (`kw=1` in call position) — are
# excluded: they don't participate in dispatch, and docstring signatures ignore
# them too (a documented `f(x; kw=1)` is stored as `Tuple{Any}`).
_is_arg(c) = !_JS.is_trivia(c) &&
    !(_JS.kind(c) in _PUNCT) && !(_JS.kind(c) in (K"parameters", K"="))

# The single recursive pass: emit `node` (at byte `offset`) under inherited `role`.
# `arity` is the call argument count to pass to link resolution for a callee node
# (or `nothing`), so a call links to the method with that many arguments.
function _emit!(io, cu, node, offset, role, arity, in_link, resolve)
    k = _JS.kind(node)
    r = _noderange(offset, node)

    # Only positions whose syntactic role vouches for the meaning get reference
    # links: call/dotcall callees (:funcall) and type positions (:type). Plain
    # value mentions (`x = foo`, `map(foo, xs)`) and binding positions (LHS of
    # `=`, definition parameters, kwarg names) stay plain — without scope
    # analysis we can't tell a documented name from a local that shadows it.
    linkable = role === :funcall || role === :type

    if _JS.is_leaf(node)
        name = k == K"Identifier" ? Symbol(_text(cu, r)) : Symbol("")
        face = _leaf_face(k, role, name, _JS.is_trivia(node))
        ref = (linkable && !in_link && resolve !== nothing && k == K"Identifier") ? resolve(_text(cu, r), arity) : nothing
        _emit_leaf(io, _text(cu, r), face, ref)
        return
    end

    # Whole dotted name (Foo.bar) resolving as one link wraps its children.
    linkhere = false
    if linkable && !in_link && resolve !== nothing && k == K"." && _is_dotted_name(node)
        ref = resolve(_text(cu, r), arity)
        if ref !== nothing
            _print_ref_open(io, ref)
            linkhere = true
        end
    end

    prefixcall = k in (K"call", K"dotcall") && _JS.is_prefix_call(node)
    # Splat arguments make the positional count a lower bound instead of exact:
    # the non-splat arguments each contribute one, the splats ≥ 0. A pure-splat
    # call (bound 0) resolves like a bare identifier.
    callee_arity = if prefixcall
        nargs = max(count(_is_arg, _JS.children(node)) - 1, 0)   # -1 for the callee
        nsplat = count(c -> _JS.kind(c) == K"...", _JS.children(node))
        if nsplat == 0
            nargs
        else
            nargs -= nsplat
            nargs > 0 ? AtLeast(nargs) : nothing
        end
    else
        nothing
    end
    dotted_target = k == K"." && role in (:funcall, :type)
    last_ident = dotted_target ? _last_ident_index(node) : 0
    symbol_quote = k == K"quote" && _is_symbol_quote(node)
    seen_coloncolon = false
    callee_done = false

    o, i = offset, 0
    for c in _JS.children(node)
        i += 1
        kc = _JS.kind(c)
        crole = role                          # default: inherit
        carity = nothing                      # arity only flows to a call's callee
        if prefixcall
            if !_JS.is_trivia(c)
                if callee_done
                    crole = :none                        # args reset
                else
                    crole, carity, callee_done = :funcall, callee_arity, true
                end
            end
        elseif k == K"::"
            crole = seen_coloncolon ? :type : :none      # RHS of `::` → type
            kc == K"::" && (seen_coloncolon = true)
        elseif k == K"curly"
            crole = :type                                 # type parameters
        elseif symbol_quote
            crole = :symbol                               # `:foo` quoted symbol
        elseif dotted_target
            crole = (i == last_ident) ? role : :none      # only the last id carries the role
            carity = (i == last_ident) ? arity : nothing
        end
        _emit!(io, cu, c, o, crole, carity, in_link || linkhere, resolve)
        o += Int(_JS.span(c))
    end

    linkhere && print(io, "</a>")
    return
end

# --- public entry points --------------------------------------------------------

function highlight_julia_html(source::AbstractString; resolve = nothing)
    cu = codeunits(source)
    tree = try
        _JS.parseall(_JS.GreenNode, source; ignore_errors = true)
    catch
        return _escape_html(source)   # fall back to plain escaped text
    end
    io = IOBuffer()
    _emit!(io, cu, tree, 0, :none, nothing, false, resolve)
    return String(take!(io))
end

# Build a memoized (name, arity)->result resolver for a block, or nothing if off.
# `arity` is the call argument count — exact `Int`, `AtLeast` lower bound for
# splatted calls, or `nothing` for an unknown count; the result is `nothing` or
# resolve_reference's `(href, targets)` NamedTuple.
# Every target that resolves is also recorded (deduplicated by href) in the
# page-level `tips` collector, which becomes the page's hidden tooltip payload.
function make_resolver(plugin, doc, page, tips = nothing)
    plugin.reference_links || return nothing
    cache = Dict{Tuple{String, Union{Int, AtLeast, Nothing}}, Any}()
    return function (name, arity)
        r = get!(() -> resolve_reference(name, doc, page, arity, plugin), cache, (name, arity))
        if r !== nothing && tips !== nothing
            for t in r.targets
                get!(tips, t.tipkey, t)
            end
        end
        return r
    end
end

# Hidden per-page tooltip payload (like doxygen's `.ttc` divs): one entry per
# unique reference target used on the page, looked up by ref-popup.js via
# `data-for`. Signatures get syntax-highlighted with the same tree backend
# (`nohighlight` so the runtime highlight.js leaves them alone). NOTE: the
# signature is a `<code>`, deliberately NOT a `<pre>` — Documenter's copy.js
# appends a copy button to every `pre` on the page, which would end up inside
# the tooltip.
function tips_html(tips)
    io = IOBuffer()
    print(io, "<div class=\"ref-tips\" hidden>")
    for key in sort!(collect(keys(tips)))
        t = tips[key]
        print(io, "<div class=\"ref-tip\" data-for=\"", _escape_html(key), "\">")
        print(
            io, "<code class=\"ref-tip-sig nohighlight\">",
            highlight_julia_html(t.sig), "</code>",
        )
        t.brief === nothing || print(io, "<p class=\"ref-tip-brief\">", _escape_html(t.brief), "</p>")
        print(io, "</div>")
    end
    print(io, "</div>")
    return String(take!(io))
end

# A script-style `jldoctest` (no `julia> ` prompt) separates code from program
# output with a lone `# output` line. Documenter decides the style the same way
# (doctests.jl: `r"^julia> "m` → REPL, else `r"^# output$"m` → script) and splits
# on `split(code, r"^# output$"m)`. REPL-style renders as `language-julia-repl`
# (handled elsewhere), so here — for a `language-julia` block — we mirror the
# script-style split and highlight only the input; the `# output` marker and the
# output below it are program output, left plain (no highlighting, no links).
const _OUTPUT_RE = r"^# output$"m

# Backend entry point: per-line highlighted HTML fragments for `source`.
# The `# output` split is applied only when `jldoctest` is true (i.e. the block
# was `jldoctest`-fenced), matching Documenter's fence-first rule.
function highlight_julia_lines(source::AbstractString, plugin, doc, page; jldoctest::Bool = false, tips = nothing)
    resolve = make_resolver(plugin, doc, page, tips)
    m = jldoctest ? match(_OUTPUT_RE, source) : nothing
    html = if m === nothing
        highlight_julia_html(source; resolve = resolve)
    else
        input = SubString(source, firstindex(source), prevind(source, m.offset))
        output = SubString(source, m.offset)   # "# output" through the end
        highlight_julia_html(input; resolve = resolve) * _escape_html(output)
    end
    return split_highlighted(html)
end

# --- julia-repl -----------------------------------------------------------------
#
# Highlight a REPL transcript: each `julia> ` (or help?>/shell>/pkg>) prompt starts
# an input expression (highlighted as Julia, with links); everything up to the next
# prompt is output (left plain). Multi-line inputs are consumed by parsing until the
# accumulated code is complete.

const _PROMPT_RE = r"(?:\A|\n)(julia> |help\?> |shell> |pkg> )"

_parses_complete(s) = !((ex = Meta.parse(s; raise = false)) isa Expr && ex.head === :incomplete)

# From byte index `start`, return (input, next_cursor), consuming whole lines until
# the accumulated code parses completely (handles multi-line REPL input).
function _repl_input_extent(source::AbstractString, start::Int)
    n = lastindex(source)
    pos = start
    while true
        nl = findnext('\n', source, pos)
        lineend = nl === nothing ? n : prevind(source, nl)
        candidate = source[start:lineend]
        if nl === nothing || _parses_complete(candidate)
            return (candidate, nl === nothing ? nextind(source, n) : nl)
        end
        pos = nextind(source, nl)
    end
    return
end

function highlight_repl_html(source::AbstractString; resolve = nothing)
    io = IOBuffer()
    prompts = collect(eachmatch(_PROMPT_RE, source))
    if isempty(prompts)
        print(io, _escape_html(source))
        return String(take!(io))
    end
    cursor = firstindex(source)
    for m in prompts
        ppos = m.offsets[1]                 # byte index of the prompt token itself
        ptext = m.captures[1]
        ppos > cursor && print(io, _escape_html(source[cursor:prevind(source, ppos)]))
        print(io, "<span class=\"julia-prompt\">", _escape_html(ptext), "</span>")
        estart = ppos + ncodeunits(ptext)
        if estart <= lastindex(source)
            input, nextcur = _repl_input_extent(source, estart)
            print(io, ptext == "julia> " ? highlight_julia_html(input; resolve = resolve) : _escape_html(input))
            cursor = nextcur
        else
            cursor = estart
        end
    end
    cursor <= lastindex(source) && print(io, _escape_html(source[cursor:end]))
    return String(take!(io))
end
