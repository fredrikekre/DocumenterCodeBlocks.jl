# Split highlighted HTML into per-line HTML fragments.
#
# Highlighter token spans can cross newlines (multiline strings/comments). At
# each newline we close every open tag, flush the line, and re-open the same
# chain on the next line so every line is a self-contained fragment. The input
# is assumed to contain only element tags and HTML-escaped text (which is what
# the highlighter emits) — a literal `<` only ever starts a tag.
#
# Julia port of the browser prototype's `splitHighlighted`.
#
# Handles any element tag (not just <span>): the highlighter also emits
# <a> reference links, which can cross a newline too (`Foo.\n    bar` is valid
# Julia) and must be closed/reopened with their own tag name. Closing tags are
# matched before opening tags. Tag interiors are `>`-free (attribute values are
# HTML-escaped), and a literal `<` in text is escaped, so `<` only starts a tag.

const _SPLIT_RE = r"(</[A-Za-z][^>]*>)|(<[A-Za-z][^>]*>)|(\n)|([^<\n]+)"

function split_highlighted(html::AbstractString)
    # Drop a single trailing newline so we don't emit a spurious empty last line.
    html = replace(html, r"\n$" => "")
    lines = String[]
    open = String[]          # stack of currently-open opening tags (full text)
    closers = String[]       # the matching closing tags, parallel to `open`
    cur = IOBuffer()
    for m in eachmatch(_SPLIT_RE, html)
        if (c = m.captures[1]) !== nothing         # closing tag </…>
            if !isempty(open)
                pop!(open)
                pop!(closers)
            end
            print(cur, c)
        elseif (t = m.captures[2]) !== nothing      # opening tag <…>
            push!(open, t)
            push!(closers, string("</", match(r"^<([A-Za-z]+)", t).captures[1], ">"))
            print(cur, t)
        elseif m.captures[3] !== nothing           # newline
            for cl in Iterators.reverse(closers)   # innermost first
                print(cur, cl)
            end
            push!(lines, String(take!(cur)))
            print(cur, join(open))
        else                                        # text run
            print(cur, m.captures[4])
        end
    end
    for cl in Iterators.reverse(closers)
        print(cur, cl)
    end
    push!(lines, String(take!(cur)))
    return lines
end
