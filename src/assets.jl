# Fully automatic asset injection.
#
# Users only add `plugins=[CodeBlocks()]` — no `assets=` entries. Before
# RenderDocument (6.0), we copy the plugin's bundled CSS/JS from the package into
# `build/assets/documentercodeblocks/` and `push!` matching entries into the HTML
# format's `assets` vector, so Documenter emits the `<head>` `<link>`/`<script>`
# tags through its own machinery (correct per-page relative paths, cached files).
#
# Which assets ship depends on config: the gutter CSS + interactions JS only when
# `line_numbers`; the popup CSS/JS only when reference popups are on.

const ASSET_DIR = normpath(joinpath(@__DIR__, "..", "assets"))

abstract type AssetStep <: DocumentPipeline end
Selectors.order(::Type{AssetStep}) = 5.5   # before RenderDocument (6.0)

function Selectors.runner(::Type{AssetStep}, doc::Documenter.Document)
    plugin = Documenter.getplugin(doc, CodeBlocks)
    "julia" in plugin.languages || return
    html = findfirst_html(doc)
    html === nothing && return

    files = String["juliasyntax-tokens.css"]
    if plugin.line_numbers
        push!(files, "line-numbers.css")
        push!(files, "line-numbers.js")
    end
    if plugin.reference_links && plugin.popups
        push!(files, "ref-popup.css")
        push!(files, "ref-popup.js")
    end

    dest = joinpath(doc.user.build, "assets", "documentercodeblocks")
    isempty(files) || mkpath(dest)
    for f in files
        cp(joinpath(ASSET_DIR, f), joinpath(dest, f); force = true)
        uri = "assets/documentercodeblocks/$(f)"
        _has_asset(html.assets, uri) || push!(html.assets, Documenter.asset(uri; islocal = true))
    end
    return
end

_has_asset(assets, uri) =
    any(a -> a isa Documenter.HTMLWriter.HTMLAsset && a.uri == uri, assets)
