# Build-time pipeline step: rewrite Julia code blocks in the rendered HTML to add
# highlighting, line numbers, and reference links.
#
# Runs after RenderDocument (order 6.0) so it can post-process build/**/*.html.

using Documenter: Documenter, Selectors
using Documenter.Builder: DocumentPipeline

abstract type CodeBlocksStep <: DocumentPipeline end

Selectors.order(::Type{CodeBlocksStep}) = 6.5   # after RenderDocument (6.0)

# Scan the AST for `jldoctest`-fenced blocks and record each block's source hash.
# Documenter's `doctest_replace!` (in the Populate step, order 5.0) rewrites the
# fence to julia/julia-repl, so we must run after ExpandTemplates (2.0, docstrings
# expanded) but before Populate (5.0), while the `jldoctest` fence still exists.
# This lets the post-render step apply the script-style `# output` split only to
# real doctests — matching Documenter's fence-first rule.
abstract type JldoctestScanStep <: DocumentPipeline end

Selectors.order(::Type{JldoctestScanStep}) = 4.5   # after ExpandTemplates (2.0), before Populate (5.0)

function Selectors.runner(::Type{JldoctestScanStep}, doc::Documenter.Document)
    plugin = Documenter.getplugin(doc, CodeBlocks)
    for page in values(doc.blueprint.pages)
        scan_jldoctests!(plugin.jldoctests, page.mdast)
    end
    return
end

function scan_jldoctests!(set::Set{UInt32}, node)
    el = node.element
    if el isa Documenter.MarkdownAST.CodeBlock && startswith(el.info, "jldoctest")
        push!(set, crc32c(el.code))
    elseif el isa Documenter.DocsNode
        # Docstring content lives in a side tree, not the node's own children.
        for md in el.mdasts
            scan_jldoctests!(set, md)
        end
    end
    for child in node.children
        scan_jldoctests!(set, child)
    end
    return
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

# The first code block of a docstring is its signature header, rendered as the
# first element of the docstring's `<section><div>` — where the `<section>` of
# an aggregated entry may carry a per-docstring sub-anchor id. By convention
# the header is not example code: any reference link would mostly be a
# self-reference, and the header isn't always valid Julia (optional-argument
# brackets like `f(x[, y])`), so it gets highlighting only — no gutter, no
# id/permalink, no links.
function _docstring_sig_prefix(html, offset)
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

function process_html(html::AbstractString, plugin::CodeBlocks, doc, page)
    seen = Dict{String, Int}()
    # Unique reference targets used on this page (href => target info), collected
    # by the resolver while blocks are processed; becomes the page's hidden
    # tooltip payload (doxygen-style, deduplicated per page).
    tips = Dict{String, Any}()
    # Manual scan (not `replace`) so each match can see its context: a block
    # directly after `<section><div>` is a docstring's signature header, and a
    # block inside a docstring suppresses self references.
    io = IOBuffer()
    pos = 1
    for m in eachmatch(BLOCK_RE, html)
        print(io, SubString(html, pos, prevind(html, m.offset)))
        content = String(m.captures[2])
        if _docstring_sig_prefix(html, m.offset)
            print(io, transform_signature_block(content))
        else
            self_ids = _enclosing_docstring_ids(html, m.offset)
            print(io, transform_block(content, plugin, doc, page, seen, tips, self_ids))
        end
        pos = m.offset + ncodeunits(m.match)
    end
    print(io, SubString(html, pos))
    html = String(take!(io))
    # REPL transcripts are highlighted too (so runtime hljs isn't needed at all).
    io = IOBuffer()
    pos = 1
    for m in eachmatch(REPL_RE, html)
        print(io, SubString(html, pos, prevind(html, m.offset)))
        self_ids = _enclosing_docstring_ids(html, m.offset)
        print(io, transform_repl_block(String(m.captures[2]), plugin, doc, page, seen, tips, self_ids))
        pos = m.offset + ncodeunits(m.match)
    end
    print(io, SubString(html, pos))
    html = String(take!(io))
    # `@repl` blocks (MultiCodeBlock pres) are rebuilt into the same transcript
    # form. A multiblock with no julia-repl input is not an `@repl` block and is
    # left untouched (transform returns nothing).
    io = IOBuffer()
    pos = 1
    for m in eachmatch(MULTIREPL_RE, html)
        print(io, SubString(html, pos, prevind(html, m.offset)))
        self_ids = _enclosing_docstring_ids(html, m.offset)
        new = transform_multirepl_block(m.captures[1], plugin, doc, page, seen, tips, self_ids)
        print(io, new === nothing ? m.match : new)
        pos = m.offset + ncodeunits(m.match)
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
# hard parse failure), but with no resolver (no reference links, no tooltip
# collection), no gutter, and no id/permalink.
function transform_signature_block(content)
    source = block_source(content)
    return string(
        "<pre><code class=\"", CODE_CLASSES, "\">",
        highlight_julia_html(source),
        "</code></pre>",
    )
end

function transform_block(content, plugin, doc, page, seen, tips, self_ids = nothing)
    source = block_source(content)
    id = block_id(source, seen)

    # Only a real `jldoctest` block gets the script-style `# output` split.
    jldoctest = crc32c(source) in plugin.jldoctests
    line_htmls = highlight_julia_lines(
        source, plugin, doc, page;
        jldoctest = jldoctest, tips = tips, self_ids = self_ids,
    )

    if !plugin.line_numbers || length(line_htmls) < plugin.min_lines
        # No gutter (line_numbers disabled, or a one-liner), but keep the
        # highlighted content and the block id + permalink.
        return plain_pre(id, CODE_CLASSES, join(line_htmls, "\n"))
    end
    return numbered_pre(id, CODE_CLASSES, line_htmls)
end

# REPL transcripts (julia-repl blocks and REPL-style jldoctests) are numbered
# too by default — linkable lines are just as useful in a transcript — but it
# has its own toggle (`repl_line_numbers`) on top of `line_numbers`.
function transform_repl_block(content, plugin, doc, page, seen, tips, self_ids = nothing)
    source = block_source(content)
    id = block_id(source, seen)
    html = highlight_repl_html(source; resolve = make_resolver(plugin, doc, page, tips, self_ids))
    if plugin.line_numbers && plugin.repl_line_numbers
        line_htmls = split_highlighted(html)
        length(line_htmls) >= plugin.min_lines && return numbered_pre(id, CODE_CLASSES, line_htmls)
    end
    return plain_pre(id, CODE_CLASSES, html)
end

# Rebuild an `@repl` MultiCodeBlock <pre> as one transcript block: input
# segments are re-highlighted from their recovered source (prompt spans, Julia
# highlighting, reference links, exactly like a julia-repl fence); output
# segments keep their inner HTML verbatim, re-wrapped in `<span class="ansi">`
# so the themes' `.ansi span.sgrNN` color rules still apply after the original
# `<code class="… ansi">` wrapper is gone; the <br/> Documenter puts between
# iterations becomes the transcript's blank line. Returns nothing when no
# segment is julia-repl input (some other language's multiblock).
function transform_multirepl_block(inner, plugin, doc, page, seen, tips, self_ids = nothing)
    segments = collect(eachmatch(MULTIREPL_SEG_RE, inner))
    isrepl(m) = m.captures[1] !== nothing && startswith(m.captures[1], "language-julia-repl")
    any(isrepl, segments) || return nothing
    resolve = make_resolver(plugin, doc, page, tips, self_ids)
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
    if plugin.line_numbers && plugin.repl_line_numbers
        line_htmls = split_highlighted(html)
        length(line_htmls) >= plugin.min_lines && return numbered_pre(id, CODE_CLASSES, line_htmls)
    end
    return plain_pre(id, CODE_CLASSES, html)
end
