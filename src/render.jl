# Emit the line-number markup and compute stable block ids.
#
# Target markup (browser-verified during prototyping):
#
#   <pre id="c-1a2b3c4d"><code class="nohighlight hljs line-numbers"
#         style="--ln-digits:3">
#     <span class="code-lines"
#       ><span class="line"><span class="line-num" aria-hidden="true"></span
#         >LINE_HTML</span
#       >…</span
#   ></code></pre>
#
# `.line-num` is a real but empty span; the digit renders from its ::before via a
# CSS counter, so numbers never end up in innerText / selection / copies.

using CRC32c: crc32c

# Reverse the HTML escaping to recover the source for hashing. Documenter's
# writer (DOM.escapehtml) escapes exactly &, <, >, " and '.
function html_unescape(s::AbstractString)
    s = replace(s, "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&#39;" => "'")
    # ampersand last so we don't double-decode (e.g. "&amp;lt;")
    return replace(s, "&amp;" => "&")
end

# Strip tags then unescape → the raw source text of a (highlighted) block.
strip_tags(html::AbstractString) = replace(html, r"<[^>]*>" => "")
block_source(inner_html::AbstractString) = html_unescape(strip_tags(inner_html))

# Content-addressed id, stable across unrelated edits elsewhere on the page.
# `seen` disambiguates same-source duplicates on one page (-2, -3, …).
function block_id(source::AbstractString, seen::Dict{String, Int})
    base = "c-" * string(crc32c(source), base = 16, pad = 8)
    n = get(seen, base, 0) + 1
    seen[base] = n
    return n == 1 ? base : string(base, "-", n)
end

# Build the `<span class="code-lines">…</span>` inner from per-line HTML fragments.
# A `start > 1` (continued line_counter, `@codeblocks line_counter = :continue`)
# offsets the CSS line counter via an inline `counter-reset` — inline style wins
# over the stylesheet's `counter-reset: line` — and exposes the start to
# line-numbers.js as `data-ln-start` (fragment L-numbers are displayed numbers).
function code_lines_html(line_htmls::Vector{String}, start::Int = 1)
    io = IOBuffer()
    if start == 1
        print(io, "<span class=\"code-lines\">")
    else
        print(
            io, "<span class=\"code-lines\" data-ln-start=\"", start,
            "\" style=\"counter-reset: line ", start - 1, "\">",
        )
    end
    for frag in line_htmls
        print(io, "<span class=\"line\"><span class=\"line-num\" aria-hidden=\"true\"></span>", frag, "</span>")
    end
    print(io, "</span>")
    return String(take!(io))
end

# Full replacement <pre> for a multi-line (numbered) block. With `start == 1`
# (the default, restart mode) the markup is exactly as before.
function numbered_pre(id::AbstractString, code_classes::AbstractString, line_htmls::Vector{String}, start::Int = 1)
    digits = length(string(start + length(line_htmls) - 1))
    style = digits > 2 ? " style=\"--ln-digits:$(digits)\"" : ""
    return string(
        "<pre id=\"", id, "\"><code class=\"", code_classes, " line-numbers\"", style, ">",
        code_lines_html(line_htmls, start),
        "</code></pre>",
    )
end

# One-liner: keep content as-is, just give the block an id (JS adds a permalink).
function plain_pre(id::AbstractString, code_classes::AbstractString, inner_html::AbstractString)
    return string("<pre id=\"", id, "\"><code class=\"", code_classes, "\">", inner_html, "</code></pre>")
end
