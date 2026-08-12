/* Verify the doxygen-style reference-link tooltips (ref-popup.js) on the built
 * docs: every link gets a hover tooltip (signature + category + brief) from the
 * per-page embedded `.ref-tips` payload; ambiguous links (data-ref-targets)
 * show a candidate signature list with the hovered candidate's tip below.
 *
 * Usage:
 *   python3 -m http.server 8907 -d ../docsite/build  # from test/ &
 *   node verify-popup.js http://localhost:8907/references/ [chromium]
 */
"use strict";

const URL_ARG = process.argv[2];
const ENGINE = process.argv[3] || "chromium";
if (!URL_ARG) {
  console.error("usage: node verify-popup.js <references-page-url> [chromium|firefox|webkit]");
  process.exit(2);
}

const pw = require("playwright");

let pass = 0,
  fail = 0;
function check(name, ok, extra) {
  if (ok) {
    pass++;
    console.log(`  ok   ${name}`);
  } else {
    fail++;
    console.log(`  FAIL ${name}${extra ? " — " + extra : ""}`);
  }
}

(async () => {
  const browser = await pw[ENGINE].launch();
  const page = await browser.newPage({
    viewport: { width: 1400, height: 950 },
    ignoreHTTPSErrors: true,
  });
  await page.goto(URL_ARG, { waitUntil: "load" });
  await page.waitForTimeout(300);

  // --- embedded payload sanity --------------------------------------------
  const nLinks = await page.locator("a.julia-ref").count();
  check("reference links present", nLinks > 0, `found ${nLinks}`);
  const nTips = await page.locator(".ref-tips .ref-tip").count();
  check("hidden per-page tips embedded", nTips >= 5, `found ${nTips}`);
  check("tips container is hidden", !(await page.locator(".ref-tips").isVisible()));
  const nAmbig = await page.locator("a.julia-ref[data-ref-targets]").count();
  check("ambiguous links carry data-ref-targets", nAmbig >= 2, `found ${nAmbig}`);

  // --- role gating: only callees and type positions link -------------------
  // foo links from 5 call positions and 2 value mentions; the binding
  // (`foo = c`) must NOT produce a link, so exactly 7 foo links exist.
  const nFoo = await page.locator('a.julia-ref[href*="foo-Tuple"]').count();
  check("value mentions link, bindings do not (7 foo links)", nFoo === 7, `found ${nFoo}`);
  // `m::MyType` annotation + `MyType(3)` callee both link.
  const nMyType = await page.locator('a.julia-ref[href$="MyType"]').count();
  check("type annotations link (2 MyType links)", nMyType >= 2, `found ${nMyType}`);
  // Macro names link too — sigil included, the module qualifier of a
  // qualified name excluded, and string-macro prefixes through their
  // `@…_str` name.
  const nTwice = await page.locator('a.julia-ref[href$="@twice"]').count();
  check("macro names link (3 @twice links)", nTwice === 3, `found ${nTwice}`);
  const twiceTexts = await page.locator('a.julia-ref[href$="@twice"]').allInnerTexts();
  check(
    "links wrap the name only (sigil in, qualifier out)",
    twiceTexts.length === 3 && twiceTexts.every((t) => t === "@twice"),
    JSON.stringify(twiceTexts)
  );
  const nWstr = await page.locator('a.julia-ref[href$="@w_str"]').count();
  check("string-macro prefix links via @w_str", nWstr === 1, `found ${nWstr}`);

  const popup = page.locator(".ref-popup");

  async function hoverAndTip(locator) {
    await page.mouse.move(5, 5);
    await page.waitForTimeout(500); // let any previous popup hide
    await locator.hover();
    await page.waitForTimeout(400);
    return popup.isVisible().catch(() => false);
  }

  // --- unambiguous link: signature + category + brief ---------------------
  const single = page.locator('a.julia-ref[href$="add_numbers"]:not([data-ref-targets])').first();
  check("tooltip appears on unambiguous hover", await hoverAndTip(single));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check("tooltip shows the signature", /add_numbers\(a, b\)/.test(sig), JSON.stringify(sig));
    check("no category in tooltip", (await popup.locator(".ref-tip-category").count()) === 0);
    check("no copy button in tooltip", (await popup.locator(".copy-button").count()) === 0);
    const brief = await popup.locator(".ref-tip-brief").innerText().catch(() => "");
    check(
      "brief is the first sentence only",
      /^Return the sum of a and b\.$/.test(brief.trim()),
      JSON.stringify(brief)
    );
    check("signature is syntax-highlighted", (await popup.locator(".ref-tip-sig .julia-funcall").count()) > 0);
  }

  // --- macro reference: tooltip like any other link -----------------------
  const macroLink = page.locator('a.julia-ref[href$="@twice"]').first();
  check("tooltip appears on macro hover", await hoverAndTip(macroLink));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check("macro tooltip shows the signature", /@twice\(expr\)/.test(sig), JSON.stringify(sig));
    check("macro name is highlighted", (await popup.locator(".ref-tip-sig .julia-macro").count()) > 0);
  }

  // --- docstring without a leading signature block → synthesized ----------
  const barLink = page.locator('a.julia-ref[href$="bar"]').first();
  check("tooltip appears for no-sig-block docstring", await hoverAndTip(barLink));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check("signature synthesized from the object", /^bar/.test(sig.trim()), JSON.stringify(sig));
    const brief = await popup.locator(".ref-tip-brief").innerText().catch(() => "");
    check("brief still extracted", /Increment a by one\./.test(brief), JSON.stringify(brief));
  }

  // --- docstring without prose → no brief ---------------------------------
  const bazLink = page.locator('a.julia-ref[href$="baz"]').first();
  check("tooltip appears for prose-less docstring", await hoverAndTip(bazLink));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check("signature from the docstring", /baz\(a\)/.test(sig), JSON.stringify(sig));
    check("no brief element", (await popup.locator(".ref-tip-brief").count()) === 0);
  }

  // --- typed signatures ----------------------------------------------------
  // neg: typed method, docstring without a signature block → synthesized WITH type
  const negLink = page.locator('a.julia-ref[href*="neg-Tuple"]').first();
  check("tooltip appears for typed synthesized sig", await hoverAndTip(negLink));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check("synthesized signature includes the type", /neg\(::Int64\)/.test(sig), JSON.stringify(sig));
    check("type annotation is highlighted", (await popup.locator(".ref-tip-sig .julia-type").count()) > 0);
  }

  // transform: parametric container + default + kwarg + where clause
  const transformLink = page.locator('a.julia-ref[href$="transform"]').first();
  check("tooltip appears for parametric sig", await hoverAndTip(transformLink));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check(
      "full parametric signature shown",
      /transform\(v::AbstractVector\{T\}, f::Function = identity; rev::Bool = false\) where \{T\}/.test(sig),
      JSON.stringify(sig)
    );
  }

  // qux: same-arity methods differing only in argument type → always ambiguous
  const quxLink = page.locator('a.julia-ref[href*="qux-Tuple"]').first();
  check("typed same-arity call is ambiguous", await hoverAndTip(quxLink));
  {
    const entries = await popup.locator(".ref-popup-targets li a").allInnerTexts();
    check(
      "list shows both TYPED signatures",
      entries.length === 2 && entries.includes("qux(x::Int)") && entries.includes("qux(x::String)"),
      JSON.stringify(entries)
    );
    const detail = await popup.locator(".ref-popup-detail").innerText().catch(() => "");
    check("typed candidate tip shown", /Double an integer\./.test(detail), JSON.stringify(detail.slice(0, 60)));
  }

  // --- many methods + arity pruning ---------------------------------------
  const measureLinks = page.locator('a.julia-ref[href*="measure-Tuple"]');
  // `measure(args...)` pure splat (unknown arity) → all six methods
  check("pure-splat call lists all six methods", await hoverAndTip(measureLinks.nth(0)));
  {
    const entries = await popup.locator(".ref-popup-targets li a").allInnerTexts();
    check("six candidates listed", entries.length === 6, JSON.stringify(entries));
  }
  // `measure(1, args...)` → at least 1 positional → 0-argument method excluded
  check("min-arity splat call shows pruned list", await hoverAndTip(measureLinks.nth(1)));
  {
    const entries = await popup.locator(".ref-popup-targets li a").allInnerTexts();
    check(
      "lower bound excludes the 0-argument method",
      entries.length === 5 && !entries.includes("measure()"),
      JSON.stringify(entries)
    );
  }
  // `measure(1)` → arity prunes to the three 1-argument methods
  check("arity-1 call shows pruned list", await hoverAndTip(measureLinks.nth(2)));
  {
    const entries = await popup.locator(".ref-popup-targets li a").allInnerTexts();
    check(
      "only the three 1-argument methods listed",
      entries.length === 3 && entries.every((e) => /^measure\(x(::\w+)?\)$/.test(e)),
      JSON.stringify(entries)
    );
  }
  // `measure(1, 2)` → exact untyped match, unambiguous tooltip
  const measure2 = page.locator('a.julia-ref[href$="measure-Tuple{Any, Any}"]').first();
  check("exact-arity match unambiguous", await hoverAndTip(measure2));
  check(
    "…with a plain tooltip, no list",
    (await popup.locator(".ref-popup-targets").count()) === 0 &&
      /Measure two things/.test(await popup.innerText())
  );

  // --- long signature headers ----------------------------------------------
  // `process(rand(3))`: arity pruning resolves to the single vector method
  const procVec = page.locator('a.julia-ref[href$="process-Tuple{AbstractVector}"]').first();
  check("arity pruning singles out one method", await hoverAndTip(procVec));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check(
      "long single-line signature shown",
      /process\(data::AbstractVector\{<:Real\}; normalize::Bool = true, atol::Real = 1e-8\)/.test(sig),
      JSON.stringify(sig)
    );
  }
  // `process(rand(3,3), ones(3))`: multi-line signature header
  const procMat = page.locator('a.julia-ref[href*="process-Tuple{AbstractMatrix"]').first();
  check("multi-line-signature tooltip appears", await hoverAndTip(procMat));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check(
      "signature keeps its three lines",
      sig.split("\n").length === 3 && /callback::Union\{Function, Nothing\}/.test(sig),
      JSON.stringify(sig)
    );
    const overflow = await popup
      .locator(".ref-tip-sig")
      .evaluate((el) => el.scrollWidth - el.clientWidth);
    check("wide signature fits without horizontal scroll", overflow <= 0, `overflow ${overflow}px`);
    const box = await popup.boundingBox();
    check("popup stays within viewport", box && box.x >= 0 && box.x + box.width <= 1400, JSON.stringify(box));
  }

  // --- aggregated docstring: arity-matched signature selection -------------
  // Arity-narrowed call sites link to the per-docstring sub-anchor of the
  // aggregated entry; the splatted call keeps the aggregate's own anchor.
  // Without sub-anchors (Documenter has no DocsNode.subslugs), arity-narrowed
  // call sites keep the aggregate's href and carry their variant tip key in
  // data-ref-tip instead — the tooltip content is identical either way, so
  // only the locators differ (mirrors SUBANCHORS in runtests.jl).
  const subanchors = (await page.locator('a.julia-ref[href*="combine-Tuple"]').count()) > 0;
  const combine2Link = subanchors
    ? page.locator('a.julia-ref[href$="combine-Tuple{Any, Any}"]').first()
    : page.locator('a.julia-ref[data-ref-tip$="combine@arity-2"]').first();
  check("arity-2 aggregate tooltip appears", await hoverAndTip(combine2Link));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    const brief = await popup.locator(".ref-tip-brief").innerText().catch(() => "");
    check(
      "arity 2 → only combine(a, b), its brief, sub-anchor href",
      sig.trim() === "combine(a, b)" && /Combine two things\./.test(brief),
      JSON.stringify({ sig, brief })
    );
  }
  const combine3Link = subanchors
    ? page.locator('a.julia-ref[href$="combine-Tuple{Any, Any, Any}"]').first()
    : page.locator('a.julia-ref[data-ref-tip$="combine@arity-3"]').first();
  check("arity-3 aggregate tooltip appears", await hoverAndTip(combine3Link));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    const brief = await popup.locator(".ref-tip-brief").innerText().catch(() => "");
    check(
      "arity 3 → only combine(a, b, c), its brief, sub-anchor href",
      sig.trim() === "combine(a, b, c)" && /Combine three things\./.test(brief),
      JSON.stringify({ sig, brief })
    );
  }
  const combineAggLink = page.locator('a.julia-ref[href$="combine"]:not([data-ref-tip])').first();
  check("unknown-arity aggregate tooltip appears", await hoverAndTip(combineAggLink));
  {
    const sig = await popup.locator(".ref-tip-sig").innerText().catch(() => "");
    check(
      "splat → all aggregated signatures listed",
      /combine\(a, b\)\ncombine\(a, b, c\)/.test(sig),
      JSON.stringify(sig)
    );
  }

  // --- multiline signature headers → collapsed one-line list labels --------
  const fitLink = page.locator('a.julia-ref[href*="fit-Tuple"]').first();
  check("multiline-header pair is ambiguous", await hoverAndTip(fitLink));
  {
    const entries = await popup.locator(".ref-popup-targets li a").allInnerTexts();
    check(
      "labels collapsed to one line (trailing comma dropped)",
      entries.length === 2 &&
        entries.includes("fit(x::AbstractVector, y::AbstractVector)") &&
        entries.includes("fit(X::AbstractMatrix, w::AbstractVector)"),
      JSON.stringify(entries)
    );
    const detailSig = await popup
      .locator(".ref-popup-detail .ref-tip-sig")
      .innerText()
      .catch(() => "");
    check(
      "detail tip keeps the verbatim multiline header",
      detailSig.split("\n").length === 4 && /^fit\($/m.test(detailSig),
      JSON.stringify(detailSig)
    );
  }

  // --- ambiguous link: signature list + hovered candidate's tip -----------
  const ambig = page.locator("a.julia-ref[data-ref-targets]").first();
  check("popup appears on ambiguous hover", await hoverAndTip(ambig));
  {
    const entries = await popup.locator(".ref-popup-targets li a").allInnerTexts();
    check(
      "list shows both candidate signatures",
      entries.length === 2 && entries.includes("foo(a)") && entries.includes("foo(a, b)"),
      JSON.stringify(entries)
    );
    check("first entry preselected", (await popup.locator(".ref-popup-targets li.selected").count()) === 1);
    const detail = await popup.locator(".ref-popup-detail").innerText().catch(() => "");
    check("selected candidate's tip shown", /one-argument method/.test(detail), JSON.stringify(detail.slice(0, 60)));
    await popup.locator(".ref-popup-targets li").nth(1).hover();
    await page.waitForTimeout(300);
    const detail2 = await popup.locator(".ref-popup-detail").innerText().catch(() => "");
    check("hovering second entry swaps tip", /two-argument method/.test(detail2), JSON.stringify(detail2.slice(0, 60)));
    check("hover-into-popup keeps it open", await popup.isVisible());
    const href = await popup.locator(".ref-popup-targets li a").nth(1).getAttribute("href");
    check(
      "entry links to the method anchor",
      /foo-Tuple\{Any,\s*Any\}/.test(decodeURIComponent(href || "")),
      href
    );
  }

  // --- dismissal ----------------------------------------------------------
  await page.mouse.move(5, 5);
  await page.waitForTimeout(600);
  check("popup hides on mouse-out", !(await popup.isVisible().catch(() => false)));

  await ambig.hover();
  await page.waitForTimeout(400);
  await page.keyboard.press("Escape");
  await page.waitForTimeout(100);
  check("Escape closes the popup", !(await popup.isVisible().catch(() => false)));

  await browser.close();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})();
