using Test
using Logging: Logging
using Documenter: Documenter
using DocInventories: Inventory, InventoryItem
using DocumenterInterLinks: InterLinks
using DocumenterCodeBlocks
const DCB = DocumenterCodeBlocks

# Whether the Documenter in use emits per-docstring sub-anchor ids on the
# `<section>`s of aggregated docstring entries (DocsNode.subslugs). With it,
# arity-narrowed references link straight to the matched docstring; without it
# (older Documenter) they fall back to the aggregate's shared anchor with
# `@arity-` variant tip keys.
const SUBANCHORS = hasfield(Documenter.DocsNode, :subslugs)

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

    # An allowlist stub resolver: records every name link resolution is asked
    # for, and links exactly the allowed ones — so link shapes can be checked
    # without a docsite build.
    function mkstub(allowed...)
        asked = String[]
        stub = function (name, arity)
            push!(asked, name)
            name in allowed || return nothing
            t = (href = "#$name", tipkey = "#$name", label = name, sig = name, brief = nothing)
            return (href = t.href, targets = [t])
        end
        return asked, stub
    end
    link(name) = "<a class=\"julia-ref\" href=\"#$name\">"

    @testset "macro names" begin
        asked, stub = mkstub(
            "@time", "f", "Foo.@bar", "@Foo.bar", "@raw_str", "@x_cmd",
            "Foo.@bar_str", "Foo.Sub.@bar_cmd", "Foo.bar", "Foo.Bar",
        )
        h(src) = DCB.highlight_julia_html(src; resolve = stub)
        # The `@` sigil is part of the link, and the arguments are not.
        @test h("@time f(x)") ==
            link("@time") * "<span class=\"julia-macro\">@</span>" *
            "<span class=\"julia-macro\">time</span></a> " *
            link("f") * "<span class=\"julia-funcall\">f</span></a>(x)"
        # Qualified names resolve as a whole but the link wraps only the name
        # (sigil included); the module qualifier and dot stay outside.
        @test startswith(
            h("Foo.@bar x"),
            "Foo<span class=\"julia-operator\">.</span>" * link("Foo.@bar") *
                "<span class=\"julia-macro\">@</span><span class=\"julia-macro\">bar</span></a>",
        )
        # In the legacy `@Foo.bar` spelling the sigil is detached from the
        # name, so only the name is wrapped.
        @test startswith(
            h("@Foo.bar x"),
            "<span class=\"julia-macro\">@</span>Foo<span class=\"julia-operator\">.</span>" *
                link("@Foo.bar") * "<span class=\"julia-macro\">bar</span></a>",
        )
        # String/cmd macros resolve through their `@…_str`/`@…_cmd` names; the
        # literal itself is not part of the link.
        @test startswith(h("raw\"hi\""), link("@raw_str") * "<span class=\"julia-macro\">raw</span></a>")
        @test startswith(h("x`cmd`"), link("@x_cmd"))
        # A qualified literal resolves under the name its binding carries.
        @test startswith(
            h("Foo.bar\"hi\""),
            "Foo<span class=\"julia-operator\">.</span>" * link("Foo.@bar_str") *
                "<span class=\"julia-macro\">bar</span></a>",
        )
        @test occursin(link("Foo.Sub.@bar_cmd") * "<span class=\"julia-macro\">bar</span></a>", h("Foo.Sub.bar`c`"))
        # Qualified function calls and type annotations get the same
        # treatment: resolve `Foo.bar`, link only `bar`.
        @test h("Foo.bar(1)") ==
            "Foo<span class=\"julia-operator\">.</span>" * link("Foo.bar") *
            "<span class=\"julia-funcall\">bar</span></a>(<span class=\"julia-number\">1</span>)"
        @test endswith(
            h("x::Foo.Bar"),
            "Foo<span class=\"julia-operator\">.</span>" * link("Foo.Bar") *
                "<span class=\"julia-type\">Bar</span></a>",
        )
        empty!(asked)
        h("@show(a, b)\n@__MODULE__\nf(@view A[1])")
        # Macro names, callees, and value mentions (the macro arguments) all
        # ask for resolution.
        @test asked == ["@show", "a", "b", "@__MODULE__", "f", "@view", "A"]
        # Nothing links without a resolver (docstring signature headers).
        @test !occursin("julia-ref", DCB.highlight_julia_html("@time f(x)"))
    end

    @testset "value mentions and bindings" begin
        # Value positions link (issue #9); binding positions do not.
        _, stub = mkstub("foo", "T", "Foo.bar")
        h(src) = DCB.highlight_julia_html(src; resolve = stub)
        # RHS of `=`, call arguments, conditions, ternary branches: values.
        @test h("x = foo") ==
            "x <span class=\"julia-keyword\">=</span>" * " " * link("foo") * "foo</a>"
        @test h("zero(T)") ==
            "<span class=\"julia-funcall\">zero</span>(" * link("T") * "T</a>)"
        @test occursin(link("foo") * "foo</a>, xs", h("map(foo, xs)"))
        @test occursin(link("foo"), h("if foo\nend"))
        @test occursin(link("Foo.bar") * "bar</a>", h("x = Foo.bar"))
        @test occursin(link("foo"), h("f(a; kw = foo)"))       # kwarg VALUE
        # Binding positions: LHS of (op-)assignment, parameters, loop
        # variables, declarations, do/lambda arguments, catch, field access.
        for src in (
                "foo = 1", "foo += 1", "foo, T = 1, 2", "for foo in xs\nend",
                "[i for foo in xs]", "foo -> 1", "local foo", "const foo = 1",
                "struct foo\n    T::Int\nend", "import Foo: foo", "using foo",
                "export foo", "try f() catch foo\nend", "f(foo = 1)",
                "foo[1] = x", "foo.x = 1", "t.foo",
            )
            @test !occursin("julia-ref", h(src))
        end
        # The value side of a binding context is ordinary code again: bodies
        # link, and so does the RHS of a `let`/`const`/default-value `=`.
        @test occursin(link("foo") * "foo</a>\n", h("function g(foo)\n    foo\nend"))
        @test occursin(link("foo"), h("g(foo) = foo + 1"))
        @test occursin(link("T"), h("const foo = T"))
        @test count("julia-ref", h("let foo = T\n    foo\nend")) == 2   # T + body foo
        @test occursin(link("foo") * "foo</a>\n", h("map(xs) do foo\n    foo\nend"))
        # Role-vouched links are unaffected by binding contexts: the annotated
        # parameter's type still links inside a signature.
        @test occursin(link("T") * "<span class=\"julia-type\">T</span></a>", h("g(x::T) = x"))
        # `binding = true` starts emission in a binding context — the mode
        # signature headers use: parameter names bind, while type annotations
        # and the `-> T` return-type position link.
        hh = DCB.highlight_julia_html("g(foo::T) -> foo"; resolve = stub, binding = true)
        @test count(link("foo"), hh) == 1               # only the return position
        @test endswith(hh, link("foo") * "foo</a>")
        @test occursin(link("T") * "<span class=\"julia-type\">T</span></a>", hh)
    end

    @testset "split_highlighted" begin
        @test DCB.split_highlighted("a\nb") == ["a", "b"]
        # A span crossing a newline is closed and reopened per line.
        @test DCB.split_highlighted("<span class=\"x\">a\nb</span>") ==
            ["<span class=\"x\">a</span>", "<span class=\"x\">b</span>"]
        # Non-span tags close/reopen with their own tag name (reference links
        # wrap only a name and rarely cross a newline, but the splitter must
        # not depend on that).
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
        # Continued numbering: start > 1 offsets the CSS counter inline and
        # exposes the start to line-numbers.js; start == 1 (restart, the
        # default) emits exactly the pre-offset markup.
        offset = DCB.numbered_pre("c-x", "k", ["a", "b"], 5)
        @test occursin("data-ln-start=\"5\"", offset)
        @test occursin("style=\"counter-reset: line 4\"", offset)
        @test !occursin("data-ln-start", DCB.numbered_pre("c-x", "k", ["a", "b"]))
        # The gutter width fits the LAST displayed number.
        @test occursin("--ln-digits:3", DCB.numbered_pre("c-x", "k", ["a", "b"], 99))
    end

    @testset "global line_counter option" begin
        # Constructor validation: Symbols only, restricted vocabulary.
        @test CodeBlocks().line_counter === :restart
        @test CodeBlocks(line_counter = :continue).line_counter === :continue
        @test CodeBlocks(line_counter = :named).line_counter === :named
        @test_throws ArgumentError CodeBlocks(line_counter = :sideways)
        @test_throws ArgumentError CodeBlocks(line_counter = "continue")
        # The global default applies to every page (here: two blocks continue
        # 1–2 → 3), and an `@codeblocks` block still overrides it
        # positionally (the third block restarts).
        mktempdir() do dir
            mkpath(joinpath(dir, "src"))
            write(
                joinpath(dir, "src", "index.md"), """
                # T

                ```julia
                a = 1
                b = 2
                ```

                ```julia
                c = 3
                ```

                ```@codeblocks
                line_counter = :restart
                ```

                ```julia
                d = 4
                ```
                """
            )
            Logging.with_logger(Logging.NullLogger()) do
                Documenter.makedocs(
                    root = dir, sitename = "t", remotes = nothing,
                    plugins = [CodeBlocks(line_counter = :continue)],
                    format = Documenter.HTML(edit_link = nothing, inventory_version = "0"),
                )
            end
            html = read(joinpath(dir, "build", "index.html"), String)
            @test [m.captures[1] for m in eachmatch(r"data-ln-start=\"(\d+)\"", html)] == ["3"]
        end
    end

    @testset "scan block kinds" begin
        # The scan must classify fences exactly like the rendered HTML the
        # post-render passes will consume: jldoctests render as julia-repl
        # iff they contain a prompt (Documenter's fence-first rule).
        kind(info, code = "x") = DCB._block_kind(Documenter.MarkdownAST.CodeBlock(info, code))
        @test kind("julia") === :block
        @test kind("julia-repl") === :repl
        @test kind("jldoctest") === :block                       # script style
        @test kind("jldoctest", "julia> 1\n1") === :repl         # REPL style
        @test kind("jldoctest label; filter = r\"x\"") === :block
        @test kind("text") === nothing
        @test kind("nohighlight") === nothing
        @test kind("") === nothing
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

    @testset "external links" begin
        # Names without a local docstring fall back to the inventories of a
        # DocumenterInterLinks plugin found in doc.plugins (no configuration on
        # the CodeBlocks side). Built fully offline from an Inventory instance.
        # NOTE: InterLinks' `alias_methods_as_function` aliases are only added
        # for inventories loaded from file/URL, not Inventory instances — hence
        # plain (non-method) names in the fake items.
        inv = Inventory(
            project = "Extern", version = "1.2.3",
            root_url = "https://example.invalid/Extern/stable/",
            items = [
                InventoryItem(name = "Extern.frobnicate", role = "function", uri = "api/#Extern.frobnicate"),
                InventoryItem(name = "Base.sort", role = "function", uri = "base/#Base.sort"),
                InventoryItem(name = "Base.@time", role = "macro", uri = "base/#Base.@time"),
                InventoryItem(name = "DocumenterCodeBlocks.CodeBlocks", role = "type", uri = "fake/#DocumenterCodeBlocks.CodeBlocks"),
                InventoryItem(name = "Onlystd.thing", domain = "std", role = "label", uri = "labels/#thing"),
            ],
        )
        page = """
            # T

            ```julia
            sort([2, 1])
            @time 1
            Extern.frobnicate(1)
            Onlystd.thing
            frobnicate(1)
            plugin = CodeBlocks()
            ```

            ```@docs
            DocumenterCodeBlocks.CodeBlocks
            ```
            """
        build(; plugins) = mktempdir() do dir
            mkpath(joinpath(dir, "src"))
            write(joinpath(dir, "src", "index.md"), page)
            Logging.with_logger(Logging.NullLogger()) do
                Documenter.makedocs(
                    root = dir, sitename = "t", remotes = nothing, plugins = plugins,
                    format = Documenter.HTML(edit_link = nothing, inventory_version = "0"),
                )
            end
            return read(joinpath(dir, "build", "index.html"), String)
        end
        links = Logging.with_logger(Logging.NullLogger()) do
            InterLinks("Extern" => inv)
        end

        html = build(plugins = [CodeBlocks(), links])
        root = "https://example.invalid/Extern/stable/"
        # Undocumented-locally names link out, marked external, via the
        # fully qualified binding slug — including macros.
        @test occursin(
            "<a class=\"julia-ref external\" href=\"$(root)base/#Base.sort\">" *
                "<span class=\"julia-funcall\">sort</span>", html,
        )
        @test occursin("href=\"$(root)base/#Base.@time\"", html)
        # Verbatim dotted-name fallback: module `Extern` is not loaded here.
        @test occursin("href=\"$(root)api/#Extern.frobnicate\"", html)
        # External targets get a minimal tooltip naming the linked project.
        @test occursin("data-for=\"$(root)base/#Base.sort\"", html)
        @test occursin("External documentation (Extern 1.2.3).", html)
        # std-domain entries (section labels) never match code identifiers.
        @test !occursin("labels/#thing", html)
        # Bare undefined identifiers don't reach the inventories.
        @test !occursin("Extern/stable/\">frobnicate", html) && !occursin("#frobnicate", html)
        # A local docstring wins over an inventory entry for the same name.
        @test occursin(
            "<a class=\"julia-ref\" href=\"#DocumenterCodeBlocks.CodeBlocks\">" *
                "<span class=\"julia-funcall\">CodeBlocks</span>", html,
        )
        @test !occursin("fake/#DocumenterCodeBlocks.CodeBlocks", html)

        # Opt-out kwarg: nothing links externally (local links remain).
        html = build(plugins = [CodeBlocks(external_links = false), links])
        @test !occursin("julia-ref external", html)
        @test !occursin("example.invalid", html)
        @test occursin("href=\"#DocumenterCodeBlocks.CodeBlocks\"", html)

        # No InterLinks plugin at all: unchanged output, no external links.
        html = build(plugins = [CodeBlocks()])
        @test !occursin("julia-ref external", html)
        @test !occursin("example.invalid", html)
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
        cont = read(joinpath(build, "continued", "index.html"), String)

        link_hrefs(html, frag) = [
            m.captures[1] for m in eachmatch(r"<a class=\"julia-ref\" href=\"([^\"]*)\"", html)
                if occursin(frag, m.captures[1])
        ]

        @testset "role-gated reference links" begin
            # foo links from 5 call positions (one qualified) plus 2 value
            # mentions (`c = foo`, `map(foo, …)`); the binding `foo = c` and
            # the plain-text mentions must not link.
            @test length(link_hrefs(refs, "foo-Tuple")) == 7
            # The value mention has an unknown arity: both methods listed.
            @test occursin(
                r"c <span class=\"julia-keyword\">=</span> <a class=\"julia-ref\" href=\"[^\"]*foo-Tuple\{Any\}\"[^>]*data-ref-targets",
                refs,
            )
            # The binding stays plain: `foo = c` emits no link around foo.
            @test occursin(r"\bfoo <span class=\"julia-keyword\">=</span> c\b", refs)
            # The qualified call's link wraps the name only.
            @test occursin(
                r"DocumenterCodeBlocks<span class=\"julia-operator\">\.</span><a class=\"julia-ref\" href=\"[^\"]*foo-Tuple\{Any\}\"[^>]*><span class=\"julia-funcall\">foo</span></a>",
                refs,
            )
            # `m::MyType` annotation + `MyType(3)` callee both link.
            @test length(link_hrefs(refs, "MyType")) == 2
            # An undocumented name stays plain.
            @test !occursin("undocumented_helper</a>", refs)
        end

        @testset "macro reference links" begin
            # `@twice` is referenced unqualified, qualified, and as a call;
            # `w"hello"` links through the `@w_str` name of the string macro.
            @test length(link_hrefs(refs, "@twice")) == 3
            @test length(link_hrefs(refs, "@w_str")) == 1
            # The `@` sigil is inside the link; a qualified call's module
            # prefix and dot stay outside it.
            @test occursin(
                r"julia-ref\" href=\"[^\"]*@twice\"[^>]*><span class=\"julia-macro\">@</span><span class=\"julia-macro\">twice</span></a>",
                refs,
            )
            @test occursin(
                r"DocumenterCodeBlocks<span class=\"julia-operator\">\.</span><a class=\"julia-ref\" href=\"[^\"]*@twice\"[^>]*><span class=\"julia-macro\">@</span><span class=\"julia-macro\">twice</span></a>",
                refs,
            )
            # An undocumented macro is highlighted but not linked.
            @test occursin("<span class=\"julia-macro\">undocumented_macro</span>", refs)
            @test !occursin("undocumented_macro</span></a>", refs)
            # Macros get tooltips like any other reference.
            @test occursin(r"data-for=\"[^\"]*@twice\"><code class=\"ref-tip-sig", refs)
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
            combine_hrefs = link_hrefs(refs, "combine")
            if SUBANCHORS
                # Aggregated docstring: arity-narrowed call sites link to the
                # per-docstring sub-anchors of the aggregate, and their tips
                # are keyed by those (already arity-specific) hrefs; the
                # splatted call keeps the aggregate's shared anchor. No
                # `@arity-` variant keys or `data-ref-tip` attributes are
                # needed once sub-anchors exist.
                @test count(h -> endswith(h, "combine-Tuple{Any, Any}"), combine_hrefs) == 1
                @test count(h -> endswith(h, "combine-Tuple{Any, Any, Any}"), combine_hrefs) == 1
                @test count(h -> endswith(h, ".combine"), combine_hrefs) == 1
                @test occursin(r"data-for=\"[^\"]*combine-Tuple\{Any, Any\}\"", refs)
                @test occursin(r"data-for=\"[^\"]*combine-Tuple\{Any, Any, Any\}\"", refs)
                @test !occursin("@arity-", refs)
                @test !occursin("data-ref-tip=", refs)
            else
                # Without sub-anchors: shared href, per-arity variant tips.
                @test all(h -> endswith(h, ".combine"), combine_hrefs)
                @test occursin("combine@arity-2", refs) && occursin("combine@arity-3", refs)
                @test count("data-ref-tip=", refs) >= 2
            end
            # Multiline signature headers collapse to one-line list labels.
            @test occursin("fit(x::AbstractVector, y::AbstractVector)", refs)
        end

        # The <details> element of the docstring anchored at `id`.
        function docstring_details(html, id)
            o = findfirst("<summary id=\"$id\">", html)
            @assert o !== nothing
            c = findnext("</details>", html, last(o))
            return SubString(html, first(o), last(c))
        end
        # A docstring's signature header block (its leading code block).
        sig_header(details) = match(
            r"<section[^>]*><div><pre><code class=\"nohighlight hljs\">(.*?)</code></pre>"s,
            details,
        ).captures[1]

        @testset "signature headers in docstrings" begin
            # The leading code block of a docstring gets no id/gutter.
            @test occursin("<section><div><pre><code class=\"nohighlight hljs\">", index)
            @test !occursin("<section><div><pre id=", index)
            # Both headers of the aggregated `combine` entry are stripped —
            # with sub-anchors their `<section>`s carry per-docstring ids.
            @test length(
                collect(
                    eachmatch(
                        r"<section( id=\"[^\"]*combine-Tuple\{[^\"]*\")?><div><pre><code class=\"nohighlight hljs\"><span class=\"julia-funcall\">combine</span>",
                        index,
                    )
                )
            ) == 2
            @test occursin("<section id=\"", index) == SUBANCHORS
            # Documented types in a header link (issue #11): clone's header
            # references MyType as argument annotation AND `->` return type.
            clone = sig_header(docstring_details(index, "DocumenterCodeBlocks.clone"))
            @test count("julia-ref\" href=\"#DocumenterCodeBlocks.MyType\"", clone) == 2
            # The documented name itself and the parameters stay plain.
            @test !occursin("julia-ref\" href=\"#DocumenterCodeBlocks.clone", clone)
            @test occursin("<span class=\"julia-funcall\">clone</span>(m", clone)
            # A same-arity typed sibling is a self reference too: the header of
            # qux(x::String) must not link `qux` through qux(x::Int)'s anchor
            # (the candidate targets include the enclosing docstring).
            quxs = sig_header(docstring_details(index, "DocumenterCodeBlocks.qux-Tuple{String}"))
            @test !occursin("julia-ref", quxs)
        end

        @testset "self references in docstrings" begin
            selflink(id) = "julia-ref\" href=\"#$id\""
            # foo(i) inside foo(a)'s docstring is a self reference: not linked.
            # Other documented names in the same block still link.
            foo1 = docstring_details(index, "DocumenterCodeBlocks.foo-Tuple{Any}")
            @test !occursin(selflink("DocumenterCodeBlocks.foo-Tuple{Any}"), foo1)
            @test occursin("julia-ref\" href=\"#DocumenterCodeBlocks.add_numbers\"", foo1)
            # foo(a, b)'s docstring (a REPL doctest): the two-argument self call
            # is not linked, but foo(1) resolves to the other method and links.
            foo2 = docstring_details(index, "DocumenterCodeBlocks.foo-Tuple{Any, Any}")
            @test !occursin(selflink("DocumenterCodeBlocks.foo-Tuple{Any, Any}"), foo2)
            @test occursin(selflink("DocumenterCodeBlocks.foo-Tuple{Any}"), foo2)
            # A macro name inside its own docstring is a self reference too,
            # while other documented names in the block still link.
            twice = docstring_details(index, "DocumenterCodeBlocks.@twice")
            @test !occursin(selflink("DocumenterCodeBlocks.@twice"), twice)
            @test occursin(selflink("DocumenterCodeBlocks.greet"), twice)
            # Constructor call in the type's own docstring is a self reference.
            @test !occursin(
                selflink("DocumenterCodeBlocks.MyType"),
                docstring_details(index, "DocumenterCodeBlocks.MyType"),
            )
            # Inside one docstring of the aggregated `combine` entry, the
            # same-arity call is a self reference (its sub-anchor is the
            # enclosing section), while the three-argument call links to the
            # sibling docstring's sub-anchor. Without sub-anchors both calls
            # resolve to the aggregate's own anchor and stay unlinked.
            combine = docstring_details(index, "DocumenterCodeBlocks.combine")
            @test !occursin(selflink("DocumenterCodeBlocks.combine-Tuple{Any, Any}"), combine)
            @test !occursin(selflink("DocumenterCodeBlocks.combine"), combine)
            if SUBANCHORS
                @test occursin(selflink("DocumenterCodeBlocks.combine-Tuple{Any, Any, Any}"), combine)
            else
                @test !occursin("julia-ref\" href=\"#DocumenterCodeBlocks.combine", combine)
            end
        end

        @testset "line numbers" begin
            # All zoo blocks are numbered, including the one-liner (min_lines=1).
            @test count("class=\"nohighlight hljs line-numbers\"", zoo) == 6
            @test !occursin("language-julia", zoo)   # runtime hljs must skip everything
            # REPL transcripts get gutters and highlighted prompts/input.
            @test occursin("julia-prompt", skip)
            @test occursin(r"line-numbers[^>]*>.{0,200}julia-prompt"s, skip)
        end

        @testset "@codeblocks continued numbering" begin
            # One running counter in document order, across block kinds:
            # julia 1–4 → repl 5–6 → @repl 7–10 → one-liner 11 → (docstring)
            # → 12–13 → 14–16 → restart back to 1; then the named-series
            # section (its two continuing blocks start at 3 each). Only
            # offset blocks carry the attribute; the sequence pins both the
            # offsets and the fact that the docstring in the middle does not
            # advance the counter.
            @test [m.captures[1] for m in eachmatch(r"data-ln-start=\"(\d+)\"", cont)] ==
                ["5", "7", "11", "12", "14", "3", "3"]
            # The inline style offsets the CSS counter next to the attribute.
            @test occursin(
                "<span class=\"code-lines\" data-ln-start=\"5\" style=\"counter-reset: line 4\">",
                cont,
            )
            # The executed @repl block participates in the continuation.
            @test occursin(r"data-ln-start=\"7\"[^>]*>.{0,400}julia-prompt"s, cont)
            # Default mode is untouched: no other page carries offset markup.
            for html in (index, refs, zoo, skip, doct)
                @test !occursin("data-ln-start", html)
                @test !occursin("counter-reset", html)
            end
            # The docstring on the page is its own page: its example block has
            # no offset markup, but still gets reference links (and self
            # suppression for stepwise itself).
            stepdoc = docstring_details(cont, "DocumenterCodeBlocks.stepwise")
            @test !occursin("data-ln-start", stepdoc)
            @test occursin(r"julia-ref\" href=\"[^\"]*add_numbers\"", stepdoc)
            @test !occursin("stepwise</span></a>", stepdoc)
            # line_counter = :named: the @example series-a pair continues
            # 1–2 → 3 across unrelated blocks (the second block is the
            # one-liner `a3 = a2 + 1`), and the named REPL-style jldoctest
            # pair continues 1–2 → 3–4 independently. Unnamed blocks and
            # other series in between restart (no data-ln-start).
            @test occursin(
                r"data-ln-start=\"3\"[^>]*style=\"counter-reset: line 2\"[^>]*>.{0,300}a3",
                cont,
            )
            @test occursin(r"data-ln-start=\"3\"[^>]*>.{0,300}julia-prompt"s, cont)
            # The series-b block (different name) starts a fresh series: no
            # offset markup on its enclosing <pre>.
            ib1 = findfirst(">b1 ", cont)
            @test ib1 !== nothing
            b1block = SubString(
                cont, first(findprev("<pre", cont, first(ib1))),
                last(findnext("</pre>", cont, first(ib1))),
            )
            @test !occursin("data-ln-start", b1block)
        end

        @testset "positional CurrentModule" begin
            # Before the mid-page switch, unqualified DemoInner names must not
            # resolve; after it they do — and the parent module's names stop
            # resolving unqualified. Both value mentions stay plain text:
            @test occursin(r"y <span class=\"julia-keyword\">=</span> inner_fn\b", cont)
            @test occursin(r"u <span class=\"julia-keyword\">=</span> add_numbers\b", cont)
            # inner_fn links from the switch block and the two restart blocks
            # (its own docstring call is a self reference); inner_helper also
            # links from the named-section block and inner_fn's docstring.
            @test length(link_hrefs(cont, "DemoInner.inner_fn")) == 3
            @test length(link_hrefs(cont, "DemoInner.inner_helper")) == 4
            # The @repl block resolves its QUALIFIED reference even though the
            # page-final CurrentModule is DemoInner (where the qualifier does
            # not resolve): per-block meta, not page-final state.
            @test occursin(
                r"data-ln-start=\"7\"[^>]*>.{0,600}julia-ref\" href=\"[^\"]*add_numbers\""s,
                cont,
            )
            # A docstring resolves in its own module wherever it lands:
            # inner_fn's example links inner_helper via DemoInner.
            innerdoc = docstring_details(cont, "DocumenterCodeBlocks.DemoInner.inner_fn")
            @test occursin(
                "julia-ref\" href=\"#DocumenterCodeBlocks.DemoInner.inner_helper\"",
                innerdoc,
            )
        end

        @testset "@repl blocks" begin
            # The @repl multiblock (one <pre> of display:block <code> children)
            # is rebuilt into a transcript block like a julia-repl fence: no
            # trace of the original markup survives (issue #3).
            @test !occursin("<code class=\"language-julia-repl", skip)
            @test !occursin("style=\"display:block;\"", skip)
            # Input is highlighted (`import`/`20` occur only in the @repl block)
            # and reference-linked.
            @test occursin("julia-keyword\">import</span>", skip)
            @test occursin(
                r"DocumenterCodeBlocks<span class=\"julia-operator\">\.</span><a class=\"julia-ref\" href=\"[^\"]*add_numbers\"[^>]*><span class=\"julia-funcall\">add_numbers</span></a>\(<span class=\"julia-number\">20</span>",
                skip,
            )
            # Output segments keep their content, wrapped for ANSI color rules.
            @test occursin("<span class=\"ansi\">3</span>", skip)
            @test occursin("<span class=\"ansi\">42</span>", skip)
        end

        @testset "doctest handling" begin
            # Script-style jldoctest: input highlighted, `# output` and below plain.
            @test occursin("foo and add_numbers are functions", doct)
            out = match(r"# output(.{0,120})"s, doct)
            @test out !== nothing && !occursin("julia-ref", out.captures[1])
        end
    end
end
