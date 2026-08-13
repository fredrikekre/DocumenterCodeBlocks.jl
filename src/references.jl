# Reference links — resolve an identifier in a code block to its docstring URL.
#
# Reuses Documenter's @ref machinery exactly as `docsxref` does
# (cross_references.jl): DocSystem.binding → find_object → doc.internal.objects →
# slugify, with per-page :CurrentModule context. The page-relative URL is built
# with faithful ports of Documenter's own get_url / pretty_url / relhref
# (HTMLWriter.jl) so links match `@ref` links exactly. Returns `nothing` when the
# name is not a documented object (then it stays plain text).

using Documenter: Documenter
import Documenter.DocSystem
using DocumenterInterLinks: InterLinks
using DocInventories: DocInventories

# `page.build` is the pre-prettyurl `.md` destination under doc.user.build, so its
# path relative to the build dir is exactly the page key (e.g. "references.md").
page_key(doc, page) = relpath(page.build, doc.user.build)

# Ports of Documenter.HTMLWriter internals (kept minimal and faithful).
function _get_url(path::AbstractString, prettyurls::Bool)
    if prettyurls
        d = basename(path) == "index.md" ? dirname(path) : first(splitext(path))
        return isempty(d) ? "index.html" : "$d/index.html"
    else
        return string(splitext(path)[1], ".html")
    end
end
function _pretty_url(path::AbstractString, prettyurls::Bool)
    if prettyurls
        dir, file = splitdir(path)
        file == "index.html" && return length(dir) == 0 ? "" : "$(dir)/"
    end
    return path
end
function _relhref(from::AbstractString, to::AbstractString)
    pagedir = dirname(from)
    return replace(relpath(to, isempty(pagedir) ? "." : pagedir), r"[/\\]+" => "/")
end

# Resolve `name` (as used in a code block on `page`) to its docstring link.
# Returns `nothing` when the name is not a documented object, else a NamedTuple
# `(href, targets)`: `href` is the primary URL (same target `@ref` would pick) and
# `targets` holds one `_target_info` per candidate — length 1 normally, or ALL
# documented objects for the binding when the reference is ambiguous (neither the
# exact typesig nor the dispatch probe singled one out). The targets feed the
# doxygen-style hover tooltips (signature list + per-page tip payloads).
# `mod` is the module the block resolves in — its positional `CurrentModule`
# (or the docstring's own module), from the ScanStep; `nothing` falls back to
# the page-final state (blocks the scan did not see).
function resolve_reference(name::AbstractString, doc, page, arity = nothing, plugin = nothing, mod = nothing)
    page === nothing && return nothing
    mod === nothing && (mod = get(page.globals.meta, :CurrentModule, Main))

    # Parse the identifier; accept a bare symbol, a dotted path (Foo.bar), or a
    # macro name (`@time`, `Foo.@bar`, `@raw_str`) — the latter parses as a
    # `:macrocall` whose first argument is the macro's name, a form
    # `DocSystem.binding` already knows how to resolve.
    ex = try
        Meta.parse(name)
    catch
        return nothing
    end
    (ex isa Symbol || (ex isa Expr && (ex.head === :. || ex.head === :macrocall))) ||
        return nothing

    binding = try
        DocSystem.binding(mod, ex)
    catch
        nothing
    end
    if binding === nothing
        # The module is not loaded in the docs environment; a qualified name can
        # still be looked up verbatim in external inventories (their slugs are
        # fully qualified, and macro spellings match: `Foo.@bar`, `Foo.@bar_str`).
        return occursin(".", name) ? _external_reference(doc, plugin, name) : nothing
    end

    # When the identifier is a call of known arity, ask for a method with that
    # many arguments (`Tuple{Any,…}`) so `foo(1, 2)` links to the `foo(a, b)`
    # docstring rather than the first-documented method. `find_object` matches the
    # method for us (exact for untyped signatures, dispatch fallback otherwise) and
    # still returns the sole object for single-method bindings. An unknown count
    # (`nothing`, or an `AtLeast` lower bound from a splatted call) uses
    # `Union{}` = "any method" → the first-documented one; the bound still prunes
    # ambiguous candidates below.
    typesig = arity isa Int ? Tuple{fill(Any, arity)...} : Union{}
    object = try
        Documenter.find_object(doc, binding, typesig)
    catch
        nothing
    end
    if object === nothing || !haskey(doc.internal.objects, object)
        # Not documented locally → try external inventories under the same fully
        # qualified slug Documenter uses ("Base.sort", "Base.@time", …). Bare
        # undefined identifiers (loop temps, …) never reach the inventories, but
        # a written-qualified name does even when currently undefined.
        (Base.Docs.defined(binding) || occursin(".", name)) || return nothing
        return _external_reference(doc, plugin, Documenter.bindingstring(binding))
    end

    prettyurls = (fmt = findfirst_html(doc)) === nothing ? true : fmt.prettyurls
    from = _get_url(page_key(doc, page), prettyurls)
    candidates = _candidate_objects(doc, binding, typesig, object, arity, plugin)
    # Arity pruning may single out one method — or exclude the fallback-resolved
    # `object` — in which case the primary link should follow the candidates.
    if length(candidates) == 1 || !(object in candidates)
        object = first(candidates)
    end
    targets = [_target_info(doc, o, from, prettyurls, arity, plugin) for o in candidates]
    # A single target's href is authoritative: an arity-narrowed aggregated
    # entry links to the matched docstring's sub-anchor, not the aggregate.
    return (
        href = length(targets) == 1 ? only(targets).href :
            _object_href(doc, object, from, prettyurls),
        targets = targets,
    )
end

# External-documentation fallback: when a name has no local docstring, look it
# up in the inventories of the user's DocumenterInterLinks plugin (the same ones
# `@extref` uses). The plugin is read from `doc.plugins` directly — the user
# configures nothing here — and NOT via `Documenter.getplugin`, which would
# construct (and cache) an empty `InterLinks` when none was passed to makedocs.
# Returns `nothing` or the `resolve_reference` shape `(href, targets)` plus
# `external = true`; the single target reuses the `_target_info` tuple shape so
# the tooltip machinery works unchanged (no docstring text exists in
# inventories, so the brief just names the linked project).
function _external_reference(doc, plugin, slug::AbstractString)
    plugin !== nothing && !plugin.external_links && return nothing
    links = get(doc.plugins, InterLinks, nothing)
    links === nothing && return nothing
    hit = _interlinks_lookup(links, slug)
    hit === nothing && return nothing
    t = (
        href = hit.href, tipkey = hit.href, label = hit.label, sig = hit.label,
        brief = "External documentation ($(hit.project)).",
    )
    return (href = hit.href, targets = [t], external = true)
end

# Look `slug` up across the InterLinks inventories: the inventory named after
# the slug's leading component first (mirroring `find_in_interlinks`'
# short-circuit), then all inventories in user-declared order. Returns `nothing`
# or `(href = absolute URL, label = display name, project = "Project X.Y.Z")`.
function _interlinks_lookup(links::InterLinks, slug::AbstractString)
    m = match(r"^@?(\w+)\.", slug)
    if m !== nothing
        inv = get(links.inventories, m.captures[1], nothing)
        if inv !== nothing
            hit = _inventory_lookup(inv, m.captures[1], slug)
            hit === nothing || return hit
        end
    end
    for name in links.names
        hit = _inventory_lookup(links.inventories[name], name, slug)
        hit === nothing || return hit
    end
    return nothing
end

function _inventory_lookup(inv, project::AbstractString, slug::AbstractString)
    # domain="jl" keeps std:label/std:doc entries (section titles, pages) from
    # colliding with code identifiers.
    item = DocInventories.find_in_inventory(inv, slug; domain = "jl", quiet = true)
    item === nothing && return nothing
    return (
        href = DocInventories.uri(item; root_url = inv.root_url),
        label = item.dispname == "-" ? item.name : item.dispname,
        project = isempty(inv.version) ? String(project) : string(project, " ", inv.version),
    )
end

# Page-relative URL (incl. #fragment) of a documented object, seen from the page
# whose output URL is `from`. `fragment` overrides the object's own anchor —
# used to target a per-docstring sub-anchor within an aggregated entry.
function _object_href(doc, object, from, prettyurls, fragment = nothing)
    docsnode = doc.internal.objects[object]
    to = _get_url(page_key(doc, docsnode.page), prettyurls)
    url = _pretty_url(_relhref(from, to), prettyurls)
    return string(url, "#", something(fragment, Documenter.slugify(object)))
end

# The per-docstring anchor id (DocsNode.subslugs, Documenter ≥ the sub-anchor
# feature) for docstring `idx` of an aggregated entry, or `nothing` when
# unavailable (older Documenter, out-of-range index, or no id for that entry).
function _subslug(docsnode, idx)
    (docsnode === nothing || idx === nothing) && return nothing
    hasfield(typeof(docsnode), :subslugs) || return nothing
    return idx <= length(docsnode.subslugs) ? docsnode.subslugs[idx] : nothing
end

# The link is ambiguous exactly when `Documenter.find_object` fell back to "the
# first included docstring" (cross_references.jl): more than one documented object
# for the binding, no exact typesig match, and the dispatch probe didn't land on a
# documented object either. Then all objects are candidates — pruned by call
# arity when it is known (`f(1)` can never mean a documented `f(x, y)`, and
# `f(a, b...)` — at least one argument — can never mean a documented `f()`);
# else just `object`.
function _candidate_objects(doc, binding, typesig, object, arity, plugin = nothing)
    objects = get(doc.internal.bindings, binding, Documenter.Object[])
    length(objects) > 1 || return [object]
    haskey(doc.internal.objects, Documenter.Object(binding, typesig)) && return [object]
    probe = try
        Documenter.find_object(binding, typesig)
    catch
        nothing
    end
    (probe !== nothing && probe in objects) && return [object]
    if arity !== nothing
        filtered = [o for o in objects if _accepts_arity(o.signature, arity)]
        if isempty(filtered)   # keep all (be safe), but tell the author
            _warn_once(
                plugin, "arity:" * string(binding) * ":" * _arity_key(arity),
                "no documented method of `$(binding)` takes $(_arity_str(arity)), " *
                    "but a code block calls it that way; the tooltip lists all " *
                    "documented methods. Is a method missing its docstring?",
            )
        else
            objects = filtered
        end
    end
    return objects
end

# Whether a documented signature type can take `arity` positional arguments
# (exact `Int`, or an `AtLeast` lower bound from a splatted call); `true` when
# that cannot be determined (Union{} = "any method", varargs, …).
function _accepts_arity(sig, arity)
    arities = _sig_arities(sig)
    arities === nothing && return true
    arity isa AtLeast && return any(>=(arity.n), arities)
    return arity in arities
end
function _sig_arities(sig)
    sig === Union{} && return nothing
    sig isa UnionAll && return _sig_arities(Base.unwrap_unionall(sig))
    if sig isa Union
        # Default arguments document as a Union of tuples (one per arity).
        parts = [_sig_arities(t) for t in Base.uniontypes(sig)]
        any(isnothing, parts) && return nothing
        return unique!(reduce(vcat, parts))
    end
    if sig isa DataType && sig <: Tuple
        any(Base.isvarargtype, sig.parameters) && return nothing
        return Int[length(sig.parameters)]
    end
    return nothing
end

# Build warnings ("CodeBlocks: " prefix) about docstrings whose tooltips come
# out degraded. The aim is to nudge docstring authors toward the conventions
# the tooltips (and Julia docs in general) rely on, so every message states
# the concrete fix. Deduplicated per build via plugin.warned — one report per
# docstring problem, not one per page/reference — and only emitted for
# docstrings some code block actually references.
function _warn_once(plugin, key::AbstractString, msg::AbstractString)
    (plugin === nothing || key in plugin.warned) && return
    push!(plugin.warned, key)
    @warn string("CodeBlocks: ", msg)
    return
end

_object_str(object) = object.signature === Union{} ? string(object.binding) :
    string(object.binding, " (", object.signature, ")")

_arity_str(arity::Int) = string(arity, arity == 1 ? " argument" : " arguments")
_arity_str(arity::AtLeast) = string("at least ", arity.n, arity.n == 1 ? " argument" : " arguments")

# Everything the hover tooltip needs about one target: `sig` is the signature
# block (possibly multiline; arity-matched within an aggregated docstring),
# `label` a collapsed one-line form (for disambiguation lists), `brief` the
# docstring's first sentence or `nothing`. When arity narrowing singles out one
# docstring of an aggregated entry, `href` targets that docstring's sub-anchor
# (DocsNode.subslugs) instead of the aggregate's shared anchor. `tipkey`
# identifies the tip payload: normally the href (sub-anchor hrefs are already
# arity-specific), but a narrowed aggregate WITHOUT a sub-anchor (older
# Documenter, or several docstrings still matching) gets a variant key — the
# page-level tip dict is deduplicated by key, and two call sites of different
# arity need different narrowed tips for the SAME href.
function _target_info(doc, object, from, prettyurls, arity = nothing, plugin = nothing)
    docsnode = get(doc.internal.objects, object, nothing)
    info = _sig_and_brief(docsnode, object, arity, plugin)
    name = _object_str(object)
    if info.synthesized
        _warn_once(
            plugin, "sig:" * name,
            "the docstring for `$(name)` does not start with a signature code block; " *
                "tooltips fall back to the synthesized signature `$(info.sig)`. " *
                "Start the docstring with the indented signature (the Julia convention):\n" *
                "    \"\"\"\n        $(info.sig)\n\n    ...\n    \"\"\"",
        )
    end
    if info.brief === nothing
        _warn_once(
            plugin, "brief:" * name,
            "the docstring for `$(name)` has no prose paragraph; tooltips show only " *
                "the signature. Add a short first sentence describing what it does.",
        )
    elseif info.brief_clipped
        _warn_once(
            plugin, "clip:" * name,
            "the first paragraph of the docstring for `$(name)` has no sentence " *
                "boundary within 200 characters; the tooltip brief is truncated " *
                "mid-sentence. Start the docstring with one short summary sentence.",
        )
    end
    subslug = _subslug(docsnode, info.subidx)
    href = _object_href(doc, object, from, prettyurls, subslug)
    return (
        href = href,
        tipkey = info.narrowed && subslug === nothing ?
            string(href, "@arity-", _arity_key(arity)) : href,
        label = info.label,
        sig = info.sig,
        brief = info.brief,
    )
end

_arity_key(arity::Int) = string(arity)
_arity_key(arity::AtLeast) = string(arity.n, "+")

# One-line form of a (possibly multiline) signature block, for list labels:
# collapse all whitespace, then tidy the seams a multiline layout leaves behind
# (spaces inside brackets, trailing comma before the closing paren).
function _collapse_sig(sig)
    s = replace(sig, r"\s+" => " ")
    s = replace(s, "( " => "(", " )" => ")", "[ " => "[", " ]" => "]", "{ " => "{", " }" => "}")
    s = replace(s, ",)" => ")", ",]" => "]", ",}" => "}")
    return String(strip(s))
end

# Signature, one-line label, and brief for a docstring, tolerating the many
# shapes Julia docstrings come in:
# - Signature: the LEADING code block of the relevant docstring(s). An
#   aggregated entry — a bare `@docs Mod.f` — holds one docstring per method
#   (mdasts/results/metas are parallel vectors); when the call arity is known,
#   the entry is narrowed to the docstrings whose dispatch signature
#   (`results[i].data[:typesig]`) accepts that arity, else ALL signature blocks
#   show, joined by newlines. A code block that merely appears later (e.g. in
#   Examples) is NOT a signature. Without any, the signature is synthesized
#   from the documented method object itself.
# - Label: the first signature block collapsed to one line (multiline headers
#   would otherwise show as just `foo(` in disambiguation lists).
# - Brief: the first paragraph of the narrowed docstring(s), flattened to plain
#   text and clipped to its first sentence; `nothing` without prose.
# Returns (sig, label, brief, narrowed, subidx, synthesized, brief_clipped) —
# `narrowed` says arity selection actually dropped something (the caller keys
# the tip payload on it), and `subidx` is the docstring's index within the
# entry when the narrowing singled out exactly one (else `nothing`), so the
# caller can link to its sub-anchor; the last two feed the docstring-quality
# warnings.
function _sig_and_brief(docsnode, object, arity = nothing, plugin = nothing)
    docs = @NamedTuple{sig::Union{Nothing, String}, brief::Union{Nothing, String}, clipped::Bool, typesig::Any, idx::Int}[]
    if docsnode !== nothing
        for (i, md) in enumerate(docsnode.mdasts)
            sig = nothing
            brief = nothing
            clipped = false
            first_block = true
            for child in md.children
                el = child.element
                if el isa Documenter.MarkdownAST.CodeBlock
                    first_block && (sig = String(strip(el.code)))
                elseif el isa Documenter.MarkdownAST.Paragraph && brief === nothing
                    brief, clipped = _first_sentence(_plain_text(child))
                end
                first_block = false
            end
            typesig = i <= length(docsnode.results) ?
                get(docsnode.results[i].data, :typesig, Union{}) : Union{}
            push!(docs, (sig = sig, brief = brief, clipped = clipped, typesig = typesig, idx = i))
        end
    end
    narrowed = false
    if arity !== nothing && length(docs) > 1
        matching = [d for d in docs if _accepts_arity(d.typesig, arity)]
        if isempty(matching)
            _warn_once(
                plugin, "arity:" * _object_str(object) * ":" * _arity_key(arity),
                "no docstring in the aggregated entry for `$(_object_str(object))` " *
                    "documents a method taking $(_arity_str(arity)); the tooltip " *
                    "shows all signatures. Is a method missing its docstring?",
            )
        elseif length(matching) < length(docs)
            docs = matching
            narrowed = true
        end
    end
    sigs = String[d.sig for d in docs if d.sig !== nothing]
    brief = nothing
    brief_clipped = false
    for d in docs
        d.brief === nothing || ((brief = d.brief; brief_clipped = d.clipped); break)
    end
    sig = isempty(sigs) ? _synth_signature(object) : join(sigs, "\n")
    label = _collapse_sig(isempty(sigs) ? sig : first(sigs))
    return (
        sig = sig, label = label, brief = brief, narrowed = narrowed,
        subidx = narrowed && length(docs) == 1 ? only(docs).idx : nothing,
        synthesized = isempty(sigs), brief_clipped = brief_clipped,
    )
end

# Fallback signature built from the documented object: binding name plus the
# stored method signature type (e.g. `foo(::Int, ::Int)`); just the name for
# non-method objects (typesig `Union{}`).
function _synth_signature(object)
    name = string(object.binding.var)
    sig = object.signature
    if sig isa DataType && sig <: Tuple && sig !== Union{}
        return string(name, "(", join(("::$(t)" for t in sig.parameters), ", "), ")")
    end
    return name
end

# Flatten a MarkdownAST subtree to its literal text (code spans included as-is).
function _plain_text(node)
    io = IOBuffer()
    _plain_text!(io, node)
    return String(take!(io))
end
function _plain_text!(io, node)
    el = node.element
    el isa Documenter.MarkdownAST.Text && print(io, el.text)
    el isa Documenter.MarkdownAST.Code && print(io, el.code)
    for child in node.children
        _plain_text!(io, child)
    end
    return
end

# First sentence of `text` (capped at 200 chars), whitespace-normalized.
# Also reports whether the cap truncated mid-sentence (no boundary found in a
# longer paragraph) — that feeds a docstring-quality warning.
function _first_sentence(text)
    m = match(r"^.{1,200}?[.!?](?=\s|$)"s, text)
    clipped = m === nothing && length(text) > 200
    s = m === nothing ? first(text, 200) : m.match
    s = strip(replace(s, r"\s+" => " "))
    return (isempty(s) ? nothing : String(s)), clipped
end
