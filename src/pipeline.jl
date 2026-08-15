# Build-time pipeline step: rewrite Julia code blocks in the rendered HTML to add
# highlighting, line numbers, and reference links.
#
# Runs after RenderDocument (order 6.0) so it can post-process build/**/*.html.

using Documenter: Documenter, Selectors
using Documenter.Builder: DocumentPipeline

abstract type CodeBlocksStep <: DocumentPipeline end

Selectors.order(::Type{CodeBlocksStep}) = 6.5   # after RenderDocument (6.0)

# ---------------------------------------------------------------------------
# The `@codeblocks` block: page-local plugin options, positional like `@meta`
# ---------------------------------------------------------------------------
#
#     ```@codeblocks
#     line_counter = :continue
#     ```
#
# Documenter warns about unknown keys in `@meta` blocks (hard-coded allowlist
# in its MetaBlocks expander), so the plugin brings its own meta-like block.
# The expanded node reuses `Documenter.MetaNode`: the HTML writer renders a
# MetaNode as nothing, Documenter's own meta walkers merge its dict harmlessly,
# and the ScanStep below picks the settings up positionally, exactly like
# `@meta`. The dict key is CodeBlocks-prefixed only because all MetaNode dicts
# — ours and `@meta`'s — merge into the same positional state; users never
# write it.

abstract type CodeBlocksExpander <: Documenter.Expanders.ExpanderPipeline end

Selectors.order(::Type{CodeBlocksExpander}) = 2.05   # right after MetaBlocks (2.0)
Selectors.matcher(::Type{CodeBlocksExpander}, node, page, doc) =
    Documenter.iscode(node, "@codeblocks")

const _LINE_COUNTER_KEY = :CodeBlocksLineCounter

# The option value: only `:symbol` literals are accepted (matching the
# Symbol-typed global options of `CodeBlocks`).
_option_symbol(v::QuoteNode) = v.value isa Symbol ? v.value : nothing
_option_symbol(v) = nothing

function Selectors.runner(::Type{CodeBlocksExpander}, node, page, doc)
    x = node.element
    settings = Dict{Symbol, Any}()
    lines = Documenter.find_block_in_file(x.code, page.source)
    for (ex, _) in Documenter.parseblock(x.code, doc, page; lines = lines)
        Documenter.isassign(ex) || continue
        key, value = ex.args[1], ex.args[2]
        if key === :line_counter
            mode = _option_symbol(value)
            if mode in (:restart, :continue, :named)
                settings[_LINE_COUNTER_KEY] = mode
            else
                @warn string(
                    "CodeBlocks: invalid `line_counter` value `", value,
                    "` in `@codeblocks` block in ", Documenter.locrepr(doc, page, lines),
                    "; expected :restart, :continue, or :named.",
                )
            end
        else
            @warn string(
                "CodeBlocks: unknown `@codeblocks` option `", key, "` in ",
                Documenter.locrepr(doc, page, lines), ".",
            )
        end
    end
    node.element = Documenter.MetaNode(x, settings)
    return
end

# ---------------------------------------------------------------------------
# Positional per-block metadata scan
# ---------------------------------------------------------------------------
#
# Walk each page's AST in document order, carrying the meta state — the
# resolution module (`@meta CurrentModule`) and the line-counter mode
# (`@codeblocks line_counter`) — and record, per code block, the state AT ITS
# POSITION. This mirrors how Documenter itself applies meta positionally
# (cross_references.jl re-walks pages merging each MetaNode in order, and
# overrides CurrentModule with the docstring's own module inside docstrings).
# The post-render step can then give every block the same resolution `@ref`
# would use, and the page-local line-counter mode.
#
# The scan also records the crc32c of `jldoctest`-fenced block sources:
# Documenter's `doctest_replace!` (Populate, order 5.0) rewrites the fence to
# julia/julia-repl, so this must run after ExpandTemplates (2.0, docstrings and
# `@repl`/`@example` expanded) but before Populate (5.0), while the fence still
# exists. That lets the post-render step apply the script-style `# output`
# split only to real doctests — matching Documenter's fence-first rule.
abstract type ScanStep <: DocumentPipeline end

Selectors.order(::Type{ScanStep}) = 4.5   # after ExpandTemplates (2.0), before Populate (5.0)

function Selectors.runner(::Type{ScanStep}, doc::Documenter.Document)
    plugin = Documenter.getplugin(doc, CodeBlocks)
    # Every page starts from the global defaults: `makedocs(meta = …)` seeds
    # each page's meta (like Documenter's expanders), and the plugin's
    # `line_counter` option is the site-wide default — both overridden
    # positionally by the page's own `@meta`/`@codeblocks` blocks.
    init = BlockMeta(get(doc.user.meta, :CurrentModule, Main), plugin.line_counter)
    for page in values(doc.blueprint.pages)
        scan_page!(plugin, page_key(doc, page), page.mdast, init)
    end
    return
end

# The block kind, matching which post-render pass will consume the block:
# `:block` (language-julia), `:repl` (language-julia-repl), or `nothing`
# (a language the plugin does not process). A `jldoctest` fence renders as
# julia-repl iff it contains a `julia> ` prompt — Documenter's own rule
# (doctests.jl), mirrored so the queues line up with the rendered HTML.
function _block_kind(el)
    langs = split(el.info; limit = 2)   # empty for a bare ``` fence
    lang = isempty(langs) ? "" : langs[1]
    lang == "julia" && return :block
    lang == "julia-repl" && return :repl
    startswith(lang, "jldoctest") &&
        return occursin(r"^julia> "m, el.code) ? :repl : :block
    return nothing
end

function _record_blockmeta!(plugin, pagekey, kind, hash, state)
    pagedict = get!(Dict{Tuple{Symbol, UInt32}, Vector{BlockMeta}}, plugin.blockmeta, pagekey)
    push!(get!(Vector{BlockMeta}, pagedict, (kind, hash)), state)
    return
end

# The block's series name for `line_counter = :named`: the second token of the
# fence info string (`jldoctest name`, `@example name`, `@repl name`, or a
# plain ```` ```julia name ```` — the writer renders only the first token, so
# the name never shows up in the output). Token syntax `[^\s;]+` matches
# Documenter's own name parsing; `nothing` for an unnamed block.
function _fence_name(info)
    m = match(r"^\s*[^\s;]+\s+([^\s;]+)", info)
    return m === nothing ? nothing : String(m.captures[1])
end

# Sequential fold over the tree: returns the (possibly updated) meta state so
# a MetaNode affects everything after it, while sub-scopes (docstrings, @eval
# results) cannot leak state back out.
function scan_page!(plugin, pagekey, node, state)
    el = node.element
    if el isa Documenter.MetaNode
        # Both `@meta` snapshots and our `@codeblocks` nodes land here.
        state = BlockMeta(
            get(el.dict, :CurrentModule, state.mod),
            get(el.dict, _LINE_COUNTER_KEY, state.line_counter),
        )
    elseif el isa Documenter.MarkdownAST.CodeBlock
        kind = _block_kind(el)
        if kind !== nothing
            startswith(el.info, "jldoctest") && push!(plugin.jldoctests, crc32c(el.code))
            meta = BlockMeta(state.mod, state.line_counter, _fence_name(el.info))
            _record_blockmeta!(plugin, pagekey, kind, crc32c(el.code), meta)
        end
    elseif el isa Documenter.MultiCodeBlock
        # An executed `@repl` block: the segments are CodeBlock children —
        # julia-repl inputs (prompt included, matching the rendered source)
        # and documenter-ansi outputs. Key it by the first input; a multiblock
        # without one is left untouched by the post-render pass, so it is not
        # recorded here either. The series name lives on the original fence
        # (`@repl name`), retained in `el.codeblock`. Do NOT descend: the
        # segments render as one block, not as individual julia-repl blocks.
        for child in node.children
            c = child.element
            if c isa Documenter.MarkdownAST.CodeBlock && startswith(c.info, "julia-repl")
                meta = BlockMeta(state.mod, state.line_counter, _fence_name(el.codeblock.info))
                _record_blockmeta!(plugin, pagekey, :multi, crc32c(c.code), meta)
                break
            end
        end
        return state
    elseif el isa Documenter.MultiOutput
        # An executed `@example` block: the rendered input is a plain-fence
        # CodeBlock child, so the series name (`@example name`) lives on the
        # original fence retained in `el.codeblock`. Other children are output
        # elements — recursed generically, since rendered markdown output can
        # itself embed code blocks (those carry no series name).
        name = _fence_name(el.codeblock.info)
        for child in node.children
            c = child.element
            if c isa Documenter.MarkdownAST.CodeBlock && (kind = _block_kind(c)) !== nothing
                meta = BlockMeta(state.mod, state.line_counter, name)
                _record_blockmeta!(plugin, pagekey, kind, crc32c(c.code), meta)
            else
                scan_page!(plugin, pagekey, child, state)
            end
        end
        return state
    elseif el isa Documenter.DocsNode
        # A docstring is its own page: blocks in it resolve in the docstring's
        # own module and always number from 1 (its content lives in side
        # trees, not the node's children).
        for (md, meta) in zip(el.mdasts, el.metas)
            scan_page!(plugin, pagekey, md, BlockMeta(get(meta, :module, state.mod), :restart))
        end
        return state
    elseif el isa Documenter.EvalNode
        # Rendered `@eval` output; its meta (if any) stays local like
        # Documenter's own walkers, which never descend into it.
        el.result === nothing || scan_page!(plugin, pagekey, el.result, state)
        return state
    end
    for child in node.children
        state = scan_page!(plugin, pagekey, child, state)
    end
    return state
end

# The recorded meta for the next occurrence of this block on the page, in
# document order, or `nothing` when the scan did not see it (fall back to the
# page-final state — the pre-scan behavior).
function _consume_blockmeta!(plugin, doc, page, kind, source)
    page === nothing && return nothing
    pagedict = get(plugin.blockmeta, page_key(doc, page), nothing)
    pagedict === nothing && return nothing
    q = get(pagedict, (kind, crc32c(source)), nothing)
    (q === nothing || isempty(q)) && return nothing
    return popfirst!(q)
end

# Matches a Julia code block emitted by Documenter's HTML writer. The ` hljs`
# class is present iff the block was prerendered (tolerated: we recover the plain
# source either way). `.*?` is safe: block content is HTML-escaped, so a literal
# `</code>` can never occur inside. `language-julia` followed by `( hljs)?"` won't
# match `language-julia-repl` or `language-nohighlight`.
const BLOCK_RE = r"<pre><code class=\"language-julia( hljs)?\">(.*?)</code></pre>"s
const REPL_RE = r"<pre><code class=\"language-julia-repl( hljs)?\">(.*?)</code></pre>"s

# An `@repl` block (Documenter's MultiCodeBlock) renders as ONE <pre> holding
# alternating `style="display:block;"` <code> children — each input a
# `language-julia-repl` element, each output ANSI-rendered as
# `nohighlight hljs ansi` — with a <br/> before each input after the first.
# Neither BLOCK_RE nor REPL_RE matches these (the style attribute breaks them),
# so they get their own pass (issue #3). The segment regex tokenizes the
# captured children; only display:block code and <br/> can appear at that level.
const MULTIREPL_RE = r"<pre>((?:<code class=\"[^\"]+\" style=\"display:block;\">.*?</code>|<br/>)+)</pre>"s
const MULTIREPL_SEG_RE = r"<code class=\"([^\"]+)\" style=\"display:block;\">(.*?)</code>|<br/>"s

function Selectors.runner(::Type{CodeBlocksStep}, doc::Documenter.Document)
    plugin = Documenter.getplugin(doc, CodeBlocks)
    "julia" in plugin.languages || return
    html_format = findfirst_html(doc)
    html_format === nothing && return   # no HTML output to post-process
    @info "DocumenterCodeBlocks: processing code blocks"
    # Reverse index keyed by output-relative HTML path (e.g. "references/index.html"),
    # since page.build is the pre-prettyurl .md destination, not the final file.
    prettyurls = html_format.prettyurls
    pages_by_out = Dict(
        _get_url(page_key(doc, p), prettyurls) => p for p in values(doc.blueprint.pages)
    )
    for (root, _, files) in walkdir(doc.user.build)
        for f in files
            endswith(f, ".html") || continue
            path = joinpath(root, f)
            relout = replace(relpath(path, doc.user.build), r"[/\\]+" => "/")
            page = get(pages_by_out, relout, nothing)
            html = read(path, String)
            new = process_html(html, plugin, doc, page)
            new == html || write(path, new)
        end
    end
    return
end

findfirst_html(doc) = findfirst_html(doc.user.format)
function findfirst_html(formats::AbstractVector)
    for w in formats
        w isa Documenter.HTML && return w
    end
    return nothing
end

# The plugin highlights the block itself, so mark it `nohighlight` (dropping
# `language-julia`) — that makes the runtime highlight.js skip it,
# which is what lets the plugin work with prerender=false / no node. The `hljs`
# class is kept for the themes' pre/code base styling.
const CODE_CLASSES = "nohighlight hljs"

function _preceded_by(html, offset, prefix)
    cu, pcu = codeunits(html), codeunits(prefix)
    n = length(pcu)
    offset > n || return false
    for i in 1:n
        cu[offset - n - 1 + i] == pcu[i] || return false
    end
    return true
end

# The first code block of a docstring is its signature header. By convention
# the header is not example code — it gets no gutter and no id/permalink, and
# it isn't always valid Julia (optional-argument brackets like `f(x[, y])`) —
# but the argument and return types in it do get reference links (issue #11):
# the header is emitted in a binding context, so parameter names stay plain
# while `::`/`{}` type positions and the `-> T` return-type convention link.
# The documented name itself never links: it is a self reference (candidate-
# aware, so same-arity siblings count as self too).
#
# In the rendered docstring the header is the first element of the
# `<section><div>` (`:first`) — or the one right after the paragraph holding
# the summary (`:second`), the same two positions `_signature_node` accepts in
# the AST; `nothing` anywhere else.
function _docstring_sig_position(html, offset)
    _section_div_at(html, offset) && return :first
    # Paragraphs cannot nest, so the closest preceding `<p>` opens the one the
    # block follows; nothing may sit between them.
    _preceded_by(html, offset, "</p>") || return nothing
    p = findprev("<p>", html, offset)
    return (p !== nothing && _section_div_at(html, first(p))) ? :second : nothing
end

# Whether `offset` directly follows the `<section><div>` opening a docstring's
# body — where the `<section>` of an aggregated entry may carry a per-docstring
# sub-anchor id.
function _section_div_at(html, offset)
    _preceded_by(html, offset, "<div>") || return false
    j = offset - ncodeunits("<div>") - 1   # the byte just before "<div>"
    (j >= 1 && codeunit(html, j) == UInt8('>')) || return false
    k = j
    while k >= 1 && codeunit(html, k) != UInt8('<')
        k -= 1
    end
    k >= 1 || return false
    tag = SubString(html, k, j)
    return tag == "<section>" || startswith(tag, "<section id=\"")
end

# The anchor ids of the docstring enclosing `offset`, or nothing when the
# offset is not inside one. A docstring renders as `<details class="docstring">
# <summary id="SLUG">…</summary><section id="SUBSLUG"><div>…` (one summary per
# entry; aggregated entries share one summary and one anchor, and each of their
# per-docstring `<section>`s may carry its own sub-anchor id), so the block is
# inside a docstring iff the closest preceding `<details class="docstring"` has
# not been closed yet. References that resolve back to any of these ids — the
# entry's anchor or the enclosing docstring's own sub-anchor — are self
# references and are not linked (see make_resolver).
function _enclosing_docstring_ids(html, offset)
    open = findprev("<details class=\"docstring\"", html, offset)
    open === nothing && return nothing
    close = findprev("</details>", html, offset)
    close === nothing || first(close) < first(open) || return nothing
    m = match(r"<summary id=\"([^\"]*)\"", html, first(open))
    (m === nothing || m.offset > offset) && return nothing
    ids = [String(m.captures[1])]
    sopen = findprev("<section", html, offset)
    if sopen !== nothing && first(sopen) > first(open)
        sclose = findprev("</section>", html, offset)
        if sclose === nothing || first(sclose) < first(sopen)
            sm = match(r"^<section id=\"([^\"]*)\"", SubString(html, first(sopen)))
            sm === nothing || push!(ids, String(sm.captures[1]))
        end
    end
    return ids
end

# The recovered source of the first julia-repl input of a MultiCodeBlock
# <pre>, or `nothing` when there is none (not an `@repl` block — some other
# language's multiblock, left untouched). Doubles as the block's scan key.
function _first_repl_source(inner)
    for m in eachmatch(MULTIREPL_SEG_RE, inner)
        m.captures[1] !== nothing && startswith(m.captures[1], "language-julia-repl") &&
            return block_source(m.captures[2])
    end
    return nothing
end

function process_html(html::AbstractString, plugin::CodeBlocks, doc, page)
    seen = Dict{String, Int}()
    # Unique reference targets used on this page (href => target info), collected
    # by the resolver while blocks are processed; becomes the page's hidden
    # tooltip payload (doxygen-style, deduplicated per page).
    tips = Dict{String, Any}()
    # One pass over all three block shapes in document order (their <pre> forms
    # are mutually exclusive, so the matches cannot overlap) — the running line
    # counter for `line_counter = :continue` must see the page's blocks in
    # order regardless of kind. Manual emission (not `replace`) so each match
    # can see its context: a block directly after `<section><div>` is a
    # docstring's signature header, and a block inside a docstring suppresses
    # self references.
    matches = sort!(
        vcat(
            [(m, :block) for m in eachmatch(BLOCK_RE, html)],
            [(m, :repl) for m in eachmatch(REPL_RE, html)],
            [(m, :multi) for m in eachmatch(MULTIREPL_RE, html)],
        ); by = t -> t[1].offset,
    )
    io = IOBuffer()
    pos = 1
    counter = 0   # last displayed line number of the page's processed blocks
    named = Dict{String, Int}()   # per-series counters for `line_counter = :named`
    for (m, kind) in matches
        print(io, SubString(html, pos, prevind(html, m.offset)))
        pos = m.offset + ncodeunits(m.match)
        self_ids = _enclosing_docstring_ids(html, m.offset)
        if kind === :multi
            source = _first_repl_source(m.captures[1])
            if source === nothing   # not an `@repl` block: leave untouched
                print(io, m.match)
                continue
            end
        else
            source = block_source(m.captures[2])
        end
        meta = _consume_blockmeta!(plugin, doc, page, kind, source)
        mod = meta === nothing ? nothing : meta.mod
        # A doctest or a series-named fence after the summary paragraph is
        # example code, not a signature (`_is_example_block` on the AST side).
        # Both render as `language-julia` like any other block, so only the
        # fence — recorded by the ScanStep as a jldoctest crc / a BlockMeta
        # name — tells them apart. (A block that LEADS the docstring counts as
        # the signature whatever its fence, as it always has.)
        sigpos = kind === :block ? _docstring_sig_position(html, m.offset) : nothing
        if sigpos === :first || (
                sigpos === :second && !(crc32c(source) in plugin.jldoctests) &&
                    (meta === nothing || meta.name === nothing)
            )
            # Signature headers have no gutter: no counter interaction.
            print(io, transform_signature_block(source, plugin, doc, page, tips, self_ids, mod))
            continue
        end
        # A block inside a docstring is its own page: it numbers from 1 and
        # does not advance the page counter (the scan records docstring blocks
        # with :restart, so `meta` agrees). In :named mode each named
        # series has its own counter; unnamed blocks restart.
        docstring = self_ids !== nothing
        start = if meta === nothing || docstring
            1
        elseif meta.line_counter === :continue
            counter + 1
        elseif meta.line_counter === :named && meta.name !== nothing
            get(named, meta.name, 0) + 1
        else
            1
        end
        block_html, nlines = if kind === :block
            transform_block(source, plugin, doc, page, seen, tips, self_ids, mod, start)
        elseif kind === :repl
            transform_repl_block(source, plugin, doc, page, seen, tips, self_ids, mod, start)
        else
            transform_multirepl_block(m.captures[1], plugin, doc, page, seen, tips, self_ids, mod, start)
        end
        # Every processed page block advances the page counter — restart
        # blocks too, so a later `continue` block picks up from the last
        # number the reader saw — gutter or not (`min_lines` gaps would break
        # continuity). A named block likewise advances its series counter.
        if !docstring
            counter = start + nlines - 1
            meta !== nothing && meta.name !== nothing &&
                (named[meta.name] = start + nlines - 1)
        end
        print(io, block_html)
    end
    print(io, SubString(html, pos))
    html = String(take!(io))
    if plugin.popups && !isempty(tips)
        html = replace(html, "</body>" => tips_html(tips) * "</body>"; count = 1)
    end
    return html
end

# A docstring signature header: syntax-highlighted like any block (JuliaSyntax
# tolerates the not-quite-Julia bits and falls back to plain escaped text on a
# hard parse failure), with no gutter and no id/permalink. Reference links DO
# attach to the types in it — the whole header is emitted in a binding context
# (`binding = true`), so parameter names bind and stay plain while type
# positions and the `-> T` return type link; the documented name itself is a
# (candidate-aware) self reference and never links.
function transform_signature_block(source, plugin, doc, page, tips = nothing, self_ids = nothing, mod = nothing)
    resolve = make_resolver(plugin, doc, page, tips, self_ids, mod)
    return string(
        "<pre><code class=\"", CODE_CLASSES, "\">",
        highlight_julia_html(source; resolve = resolve, binding = true),
        "</code></pre>",
    )
end

# The block transforms take the positional per-block meta — `mod`, the module
# references resolve in, and `start`, the first displayed line number
# (`> 1` under `line_counter = :continue`) — and return `(html, nlines)` so
# the caller can advance the page's running line counter.
function transform_block(source, plugin, doc, page, seen, tips, self_ids = nothing, mod = nothing, start = 1)
    id = block_id(source, seen)

    # Only a real `jldoctest` block gets the script-style `# output` split.
    jldoctest = crc32c(source) in plugin.jldoctests
    line_htmls = highlight_julia_lines(
        source, plugin, doc, page;
        jldoctest = jldoctest, tips = tips, self_ids = self_ids, mod = mod,
    )

    if !plugin.line_numbers || length(line_htmls) < plugin.min_lines
        # No gutter (line_numbers disabled, or a one-liner), but keep the
        # highlighted content and the block id + permalink.
        return plain_pre(id, CODE_CLASSES, join(line_htmls, "\n")), length(line_htmls)
    end
    return numbered_pre(id, CODE_CLASSES, line_htmls, start), length(line_htmls)
end

# REPL transcripts (julia-repl blocks and REPL-style jldoctests) are numbered
# too by default — linkable lines are just as useful in a transcript — but it
# has its own toggle (`repl_line_numbers`) on top of `line_numbers`.
function transform_repl_block(source, plugin, doc, page, seen, tips, self_ids = nothing, mod = nothing, start = 1)
    id = block_id(source, seen)
    html = highlight_repl_html(source; resolve = make_resolver(plugin, doc, page, tips, self_ids, mod))
    line_htmls = split_highlighted(html)
    if plugin.line_numbers && plugin.repl_line_numbers && length(line_htmls) >= plugin.min_lines
        return numbered_pre(id, CODE_CLASSES, line_htmls, start), length(line_htmls)
    end
    return plain_pre(id, CODE_CLASSES, html), length(line_htmls)
end

# Rebuild an `@repl` MultiCodeBlock <pre> as one transcript block: input
# segments are re-highlighted from their recovered source (prompt spans, Julia
# highlighting, reference links, exactly like a julia-repl fence); output
# segments keep their inner HTML verbatim, re-wrapped in `<span class="ansi">`
# so the themes' `.ansi span.sgrNN` color rules still apply after the original
# `<code class="… ansi">` wrapper is gone; the <br/> Documenter puts between
# iterations becomes the transcript's blank line. The caller has already
# checked for a julia-repl input (`_first_repl_source`).
function transform_multirepl_block(inner, plugin, doc, page, seen, tips, self_ids = nothing, mod = nothing, start = 1)
    segments = collect(eachmatch(MULTIREPL_SEG_RE, inner))
    isrepl(m) = m.captures[1] !== nothing && startswith(m.captures[1], "language-julia-repl")
    resolve = make_resolver(plugin, doc, page, tips, self_ids, mod)
    htmls = String[]
    sources = String[]
    for m in segments
        if m.captures[1] === nothing            # <br/>
            push!(htmls, "")
            push!(sources, "")
        else
            source = block_source(m.captures[2])
            push!(sources, source)
            if isrepl(m)
                push!(htmls, highlight_repl_html(source; resolve = resolve))
            else
                push!(htmls, string("<span class=\"ansi\">", m.captures[2], "</span>"))
            end
        end
    end
    id = block_id(join(sources, "\n"), seen)
    html = join(htmls, "\n")
    line_htmls = split_highlighted(html)
    if plugin.line_numbers && plugin.repl_line_numbers && length(line_htmls) >= plugin.min_lines
        return numbered_pre(id, CODE_CLASSES, line_htmls, start), length(line_htmls)
    end
    return plain_pre(id, CODE_CLASSES, html), length(line_htmls)
end
