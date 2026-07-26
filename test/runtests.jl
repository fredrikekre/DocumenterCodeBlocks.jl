using Test
using Logging: Logging
using DocumenterCodeBlocks
const DCB = DocumenterCodeBlocks

@testset "DocumenterCodeBlocks" begin

    @testset "highlight_julia_html" begin
        h = DCB.highlight_julia_html
        @test h("x = 1") ==
            "x <span class=\"julia-keyword\">=</span> <span class=\"julia-number\">1</span>"
        # Updating assignment renders two-tone: `+` is an operator token, `=` is
        # a separate assignment token. Broadcast `.=` is a single `=`-kind token.
        @test occursin(
            "<span class=\"julia-operator\">+</span><span class=\"julia-keyword\">=</span>",
            h("a += 1"),
        )
        @test occursin("<span class=\"julia-keyword\">.=</span>", h("a .= 1"))
        # Keyword arguments use `=` too.
        @test occursin("<span class=\"julia-keyword\">=</span>", h("f(x = 1)"))
        # Word-operators tokenize as Identifier but must still be colored.
        @test h("a * b") == "a <span class=\"julia-operator\">*</span> b"
        @test occursin("<span class=\"julia-operator\">in</span>", h("for i in xs\nend"))
        # Quoted symbols color the sigil too.
        @test occursin(
            "<span class=\"julia-symbol\">:</span><span class=\"julia-symbol\">answer</span>",
            h("s = :answer"),
        )
        # `quote … end` blocks are not symbols.
        @test !occursin("julia-symbol", h("quote\n    x\nend"))
        # Type positions color; bare type names in value position stay plain.
        @test h("x::Int") ==
            "x<span class=\"julia-operator\">::</span><span class=\"julia-type\">Int</span>"
        @test h("zeros(Int, 3)") ==
            "<span class=\"julia-funcall\">zeros</span>(Int, <span class=\"julia-number\">3</span>)"
        @test occursin("<span class=\"julia-type\">Int</span>", h("Vector{Int}()"))
        @test h("# hi") == "<span class=\"julia-comment\"># hi</span>"
        @test occursin("julia-keyword\">function</span>", h("function f()\nend"))
        @test occursin("julia-macro", h("@show x"))
        @test occursin("julia-string", h("\"hi\""))
        # Singleton identifiers.
        @test occursin("julia-symbol\">nothing</span>", h("x = nothing"))
        # HTML escaping inside strings and comments.
        @test occursin("&lt;b&gt;", h("s = \"<b>\""))
        # Multibyte source survives (code-unit slicing must stay char-aligned).
        @test occursin("δu", h("δu = α * β"))
    end

    @testset "highlight_repl_html" begin
        r = DCB.highlight_repl_html("julia> 1 + 1\n2")
        @test occursin("<span class=\"julia-prompt\">julia&gt; </span>", r)
        @test occursin("<span class=\"julia-number\">1</span>", r)   # input highlighted
        @test endswith(r, "\n2")                                     # output left plain
        # Multi-line input is consumed until the expression parses complete.
        r2 = DCB.highlight_repl_html("julia> function f()\n           1\n       end\nf (generic function with 1 method)")
        @test occursin("julia-keyword\">function</span>", r2)
        @test occursin("generic function", r2)
        @test !occursin("<span class=\"julia-funcall\">f</span> (generic", r2)
    end

    @testset "split_highlighted" begin
        @test DCB.split_highlighted("a\nb") == ["a", "b"]
        # A span crossing a newline is closed and reopened per line.
        @test DCB.split_highlighted("<span class=\"x\">a\nb</span>") ==
            ["<span class=\"x\">a</span>", "<span class=\"x\">b</span>"]
        # Non-span tags close/reopen with their own tag name (a dotted-name
        # reference link can legally cross a newline: `Foo.\n    bar`).
        @test DCB.split_highlighted("<a href=\"#\">Foo.\nbar</a>") ==
            ["<a href=\"#\">Foo.</a>", "<a href=\"#\">bar</a>"]
        # Nested mixed tags close innermost-first.
        @test DCB.split_highlighted("<a href=\"#\"><span class=\"x\">y\nz</span></a>") ==
            [
            "<a href=\"#\"><span class=\"x\">y</span></a>",
            "<a href=\"#\"><span class=\"x\">z</span></a>",
        ]
        # Trailing newline does not produce a spurious empty line.
        @test DCB.split_highlighted("a\n") == ["a"]
    end

    @testset "render helpers" begin
        @test DCB.html_unescape("&lt;a&gt; &quot;x&quot; &amp;lt;") == "<a> \"x\" &lt;"
        @test DCB.block_source("<span class=\"x\">a &amp; b</span>") == "a & b"
        seen = Dict{String, Int}()
        id1 = DCB.block_id("x = 1", seen)
        @test startswith(id1, "c-")
        @test DCB.block_id("x = 1", seen) == id1 * "-2"   # same-page duplicate
        @test DCB.block_id("x = 2", seen) != id1
    end

    @testset "arity" begin
        @test DCB._sig_arities(Tuple{Any, Any}) == [2]
        @test DCB._sig_arities(Tuple{}) == [0]
        @test DCB._sig_arities(Union{}) === nothing
        @test sort(DCB._sig_arities(Union{Tuple{Any}, Tuple{Any, Any}})) == [1, 2]
        @test DCB._sig_arities(Tuple{Vararg{Any}}) === nothing
        @test DCB._sig_arities(Tuple{T} where {T}) == [1]
        @test DCB._accepts_arity(Tuple{Any, Any}, 2)
        @test !DCB._accepts_arity(Tuple{Any, Any}, 1)
        @test DCB._accepts_arity(Union{}, 17)             # unknown → permissive
        @test DCB._accepts_arity(Tuple{Any, Any}, DCB.AtLeast(1))
        @test !DCB._accepts_arity(Tuple{}, DCB.AtLeast(1))
        @test DCB._arity_key(2) == "2"
        @test DCB._arity_key(DCB.AtLeast(3)) == "3+"
    end

    @testset "tooltip text helpers" begin
        @test DCB._collapse_sig("foo(\n    a, b, c, d\n)") == "foo(a, b, c, d)"
        @test DCB._collapse_sig("fit(\n    x::A,\n    y::B,\n)") == "fit(x::A, y::B)"
        @test DCB._collapse_sig("plain") == "plain"
        @test DCB._first_sentence("Hello world. More text.") == ("Hello world.", false)
        @test DCB._first_sentence("no boundary here") == ("no boundary here", false)
        s, clipped = DCB._first_sentence("a "^150)   # 300 chars, no sentence boundary
        @test clipped && length(s) <= 200
        @test DCB._first_sentence("   ") == (nothing, false)
    end

    @testset "docsite build" begin
        docsite = joinpath(@__DIR__, "docsite")
        # Capture only warnings: the plugin's docstring-quality nudges must fire
        # exactly once per (intentionally degraded) demo docstring.
        logger = Test.TestLogger(min_level = Logging.Warn)
        Logging.with_logger(logger) do
            include(joinpath(docsite, "make.jl"))
        end
        cb = [String(l.message) for l in logger.logs if startswith(String(l.message), "CodeBlocks: ")]
        @test length(cb) == 5
        @test any(contains("`DocumenterCodeBlocks.bar`"), cb)             # no signature block
        @test any(contains("`DocumenterCodeBlocks.baz` has no prose"), cb)
        @test any(contains("`DocumenterCodeBlocks.wordy`"), cb)           # clipped brief
        @test any(contains("neg"), cb)                                    # typed, synthesized
        @test any(contains("takes 4 arguments"), cb)                      # arity gap
        other = [String(l.message) for l in logger.logs if !startswith(String(l.message), "CodeBlocks: ")]
        @test isempty(other)   # the docsite build itself must be warning-clean

        build = joinpath(docsite, "build")
        refs = read(joinpath(build, "references", "index.html"), String)
        zoo = read(joinpath(build, "zoo", "index.html"), String)
        index = read(joinpath(build, "index.html"), String)
        skip = read(joinpath(build, "skipcases", "index.html"), String)
        doct = read(joinpath(build, "doctest-blocks", "index.html"), String)

        link_hrefs(html, frag) = [
            m.captures[1] for m in eachmatch(r"<a class=\"julia-ref\" href=\"([^\"]*)\"", html)
                if occursin(frag, m.captures[1])
        ]

        @testset "role-gated reference links" begin
            # foo appears in 4 call positions; plain value mentions must not link.
            @test length(link_hrefs(refs, "foo-Tuple")) == 4
            # `m::MyType` annotation + `MyType(3)` callee both link.
            @test length(link_hrefs(refs, "MyType")) == 2
            # An undocumented name stays plain.
            @test !occursin("undocumented_helper</a>", refs)
        end

        @testset "arity pruning and splats" begin
            targets = [
                length(collect(eachmatch(r"measure\(", m.captures[1])))
                    for m in eachmatch(r"data-ref-targets=\"([^\"]*measure[^\"]*)\"", refs)
            ]
            # measure(1) → 3 pruned; measure(1, args...) → 5 (0-arg excluded);
            # measure(args...) → all 6; measure(1, 2, 3, 4) → arity gap, all 6.
            @test sort(targets) == [3, 5, 6, 6]
            # Arity pruning follows the candidates for the primary link.
            @test !isempty(link_hrefs(refs, "process-Tuple{AbstractVector}"))
        end

        @testset "tooltip payload" begin
            @test occursin("<div class=\"ref-tips\" hidden>", refs)
            # bar: no leading signature block → synthesized bare-name signature.
            @test occursin(
                r"data-for=\"[^\"]*\.bar\"><code class=\"ref-tip-sig nohighlight\">bar</code>", refs,
            )
            # baz: docstring without prose → tip has no brief element.
            baz = match(r"<div class=\"ref-tip\" data-for=\"[^\"]*\.baz\">(.*?)</div>"s, refs)
            @test baz !== nothing && !occursin("ref-tip-brief", baz.captures[1])
            # Aggregated docstring: shared href, per-arity variant tips.
            @test occursin("combine@arity-2", refs) && occursin("combine@arity-3", refs)
            @test count("data-ref-tip=", refs) >= 2
            # Multiline signature headers collapse to one-line list labels.
            @test occursin("fit(x::AbstractVector, y::AbstractVector)", refs)
        end

        @testset "signature headers in docstrings" begin
            # The leading code block of a docstring gets highlighting only:
            # no id/gutter/links.
            @test occursin("<section><div><pre><code class=\"nohighlight hljs\">", index)
            @test !occursin("<section><div><pre id=", index)
            # Both headers of the aggregated `combine` entry are stripped.
            @test length(
                collect(
                    eachmatch(
                        r"<section><div><pre><code class=\"nohighlight hljs\"><span class=\"julia-funcall\">combine</span>",
                        index,
                    )
                )
            ) == 2
        end

        @testset "line numbers" begin
            # All zoo blocks are numbered, including the one-liner (min_lines=1).
            @test count("class=\"nohighlight hljs line-numbers\"", zoo) == 6
            @test !occursin("language-julia", zoo)   # runtime hljs must skip everything
            # REPL transcripts get gutters and highlighted prompts/input.
            @test occursin("julia-prompt", skip)
            @test occursin(r"line-numbers[^>]*>.{0,200}julia-prompt"s, skip)
        end

        @testset "doctest handling" begin
            # Script-style jldoctest: input highlighted, `# output` and below plain.
            @test occursin("foo and add_numbers are functions", doct)
            out = match(r"# output(.{0,120})"s, doct)
            @test out !== nothing && !occursin("julia-ref", out.captures[1])
        end
    end
end
