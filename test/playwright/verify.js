#!/usr/bin/env node
/* Playwright verification suite for the Documenter line-numbers feature.
 *
 * Usage:
 *   npm i playwright && npx playwright install chromium   # once (add firefox/webkit as desired)
 *   node verify.js <url> [chromium|firefox|webkit]
 * e.g.
 *   node verify.js http://localhost:8123/tutorials/heat_equation/ webkit
 *
 * Checks: DOM structure, gutter click zone, drag/shift-click selection, hash
 * restore, copy purity, sticky pinning under horizontal scroll, and the
 * six-theme gutter/background sweep.
 *
 * Implementation notes:
 * - Tests must reset the hash with history.replaceState — `location.hash = ""`
 *   NAVIGATES (scrolls to top) and invalidates previously measured coordinates.
 * - The block-id prefix is configurable below (prototype used cbN; the plugin
 *   uses content-hash ids).
 * - Allow time for network-dependent rendering (hljs/fonts) before measuring.
 */

const URL = process.argv[2];
const ENGINE = process.argv[3] || "chromium";
if (!URL) {
  console.error("usage: node verify.js <url> [chromium|firefox|webkit]");
  process.exit(2);
}

const pw = require("playwright");
let failures = 0;
function check(name, ok, detail) {
  console.log((ok ? "  PASS " : "  FAIL ") + name + (detail ? "  (" + detail + ")" : ""));
  if (!ok) failures++;
}

(async () => {
  const browser = await pw[ENGINE].launch();
  const page = await browser.newPage({ viewport: { width: 1400, height: 950 }, ignoreHTTPSErrors: true });
  await page.goto(URL, { waitUntil: "load" });
  await page.waitForTimeout(3000); // hljs prerender needs nothing; runtime variant needs CDN time

  console.log(`verify.js — ${ENGINE} — ${URL}`);

  // ---- structure ----
  const s = await page.evaluate(() => {
    const numbered = document.querySelectorAll("code.line-numbers");
    const target = Array.from(numbered).find((c) => c.querySelectorAll(".line").length >= 8);
    return {
      numbered: numbered.length,
      gutterCells: document.querySelectorAll(".line-num").length,
      targetId: target ? target.parentElement.id : null,
      targetLines: target ? target.querySelectorAll(".line").length : 0,
    };
  });
  check("numbered blocks exist", s.numbered > 0, `${s.numbered} blocks`);
  check("gutter cells exist", s.gutterCells > 0, `${s.gutterCells} cells`);
  const oneLiner = await page.evaluate(() =>
    Array.from(document.querySelectorAll("code.line-numbers")).some(
      (c) => c.querySelectorAll(".line").length === 1
    )
  );
  check("single-line block has a gutter (min_lines=1)", oneLiner);
  check("found a >=8-line target block", !!s.targetId, `#${s.targetId}, ${s.targetLines} lines`);
  if (!s.targetId) {
    await browser.close();
    process.exit(1);
  }
  const ID = s.targetId;

  const gutterPos = async (n) =>
    page.evaluate(
      ([id, n]) => {
        const c = document.querySelector("#" + CSS.escape(id) + " > code");
        c.parentElement.scrollIntoView({ block: "center" });
        const r = c.querySelectorAll(".line")[n - 1].getBoundingClientRect();
        return { x: c.getBoundingClientRect().left + 15, y: r.top + r.height / 2 };
      },
      [ID, n]
    );
  const state = () =>
    page.evaluate(() => ({ hash: location.hash, hl: document.querySelectorAll(".line.hl").length }));
  const reset = () =>
    page.evaluate(() => {
      history.replaceState(null, "", location.pathname);
      document.querySelectorAll(".line.hl").forEach((e) => e.classList.remove("hl"));
      document.querySelectorAll("pre.hl-block").forEach((e) => e.classList.remove("hl-block"));
    });

  // ---- click zone: whole gutter cell clickable, text area not ----
  await reset();
  let pos = await gutterPos(2);
  await page.mouse.click(pos.x, pos.y);
  let r = await state();
  check("gutter click selects single line", r.hl === 1 && /-L2$/.test(r.hash), r.hash);

  const zone = await page.evaluate((id) => {
    const c = document.querySelector("#" + CSS.escape(id) + " > code");
    const num = c.querySelector(".line-num");
    const nr = num.getBoundingClientRect();
    const line = c.querySelectorAll(".line")[4];
    const y = line.getBoundingClientRect().top + line.getBoundingClientRect().height / 2;
    const at = (x) => {
      const el = document.elementFromPoint(x, y);
      return el && el.classList.contains("line-num");
    };
    return { leftEdge: at(nr.left + 2), beforeBorder: at(nr.right - 2), pastGap: at(nr.right + 20) };
  }, ID);
  check("cell hit area spans left edge to border", zone.leftEdge && zone.beforeBorder, JSON.stringify(zone));
  check("text area is not gutter", zone.pastGap === false);

  // ---- drag range with live preview ----
  await reset();
  pos = await gutterPos(3);
  await page.mouse.move(pos.x, pos.y);
  await page.mouse.down();
  pos = await gutterPos(5);
  await page.mouse.move(pos.x, pos.y, { steps: 3 });
  const mid = await state();
  pos = await gutterPos(7);
  await page.mouse.move(pos.x, pos.y, { steps: 3 });
  await page.mouse.up();
  r = await state();
  check("drag shows live preview mid-drag", mid.hl === 3 && mid.hash === "", JSON.stringify(mid));
  check("drag selects range", r.hl === 5 && /-L3-L7$/.test(r.hash), r.hash);

  // ---- shift-click extends ----
  pos = await gutterPos(9);
  await page.keyboard.down("Shift");
  await page.mouse.click(pos.x, pos.y);
  await page.keyboard.up("Shift");
  r = await state();
  check("shift-click extends from drag start", r.hl === 7 && /-L3-L9$/.test(r.hash), r.hash);

  // ---- text click is a no-op ----
  const before = await state();
  await page.evaluate((id) => {
    const line = document.querySelector("#" + CSS.escape(id) + " .line");
    const lr = line.getBoundingClientRect();
    line.dispatchEvent(
      new MouseEvent("mousedown", { bubbles: true, clientX: lr.left + 250, clientY: lr.top + 4 })
    );
  }, ID);
  r = await state();
  check("click on code text does not change selection", r.hash === before.hash && r.hl === before.hl);

  // ---- deselect on outside click ----
  // A real click inside the block (on the code text) keeps the selection…
  pos = await page.evaluate((id) => {
    const line = document.querySelector("#" + CSS.escape(id) + " .line");
    const lr = line.getBoundingClientRect();
    return { x: lr.left + 250, y: lr.top + lr.height / 2 };
  }, ID);
  await page.mouse.click(pos.x, pos.y);
  r = await state();
  check("real click on code text keeps selection", r.hl === 7 && /-L3-L9$/.test(r.hash), r.hash);
  // …a click outside any code block clears the highlight and the fragment…
  await page.locator("article p").first().click();
  r = await state();
  check("click outside deselects and clears hash", r.hl === 0 && r.hash === "", JSON.stringify(r));
  // …clicking inside a DIFFERENT code block (its padding — no gutter, no link)
  // also deselects…
  pos = await gutterPos(2);
  await page.mouse.click(pos.x, pos.y); // reselect a line in the target block
  const other = await page.evaluate((id) => {
    const p = Array.from(document.querySelectorAll('pre[id^="c-"]')).find((x) => x.id !== id);
    p.scrollIntoView({ block: "center" });
    const b = p.getBoundingClientRect();
    return { x: b.right - 8, y: b.bottom - 8 };
  }, ID);
  await page.mouse.click(other.x, other.y);
  r = await state();
  check("click in another block deselects", r.hl === 0 && r.hash === "", JSON.stringify(r));
  // …selecting a line in another block via its gutter replaces the selection
  // (the drag's synthesized click must not clear the brand-new selection)…
  pos = await gutterPos(4);
  await page.mouse.click(pos.x, pos.y);
  const swapped = await page.evaluate((id) => {
    const p = Array.from(document.querySelectorAll("code.line-numbers")).find(
      (c) => c.parentElement.id !== id && c.querySelectorAll(".line").length >= 2
    );
    p.parentElement.scrollIntoView({ block: "center" });
    const r0 = p.querySelectorAll(".line-num")[0].getBoundingClientRect();
    return { x: r0.left + r0.width / 2, y: r0.top + r0.height / 2, id: p.parentElement.id };
  }, ID);
  await page.mouse.click(swapped.x, swapped.y);
  r = await state();
  check(
    "gutter click in another block swaps the selection",
    r.hl === 1 && r.hash.indexOf(swapped.id) === 1,
    JSON.stringify(r)
  );
  await reset();
  // …and the click event synthesized for a drag that ends OUTSIDE the block
  // (it fires on the common ancestor) must not undo the drag's own selection.
  pos = await gutterPos(3);
  await page.mouse.move(pos.x, pos.y);
  await page.mouse.down();
  const below = await page.evaluate((id) => {
    const b = document.getElementById(id).getBoundingClientRect();
    return { x: b.left + 40, y: Math.min(b.bottom + 60, window.innerHeight - 5) };
  }, ID);
  await page.mouse.move(below.x, below.y, { steps: 3 });
  await page.mouse.up();
  r = await state();
  check("drag ending outside keeps its selection", r.hl >= 1 && /-L3-L\d+$/.test(r.hash), r.hash);

  // ---- copy purity ----
  const copy = await page.evaluate((id) => {
    const pre = document.getElementById(id);
    const lines = pre.querySelectorAll(".line");
    const expected = Array.from(lines).map((s) => s.textContent).join("\n");
    return pre.innerText.replace(/\n$/, "") === expected;
  }, ID);
  check("pre.innerText has no gutter digits / doubled newlines", copy);

  // ---- permalink button: real anchor, copies block/selection URL (#17) ----
  // Clipboard content can only be read back in chromium (grantPermissions);
  // the anchor/hash/feedback checks run everywhere.
  let canReadClipboard = false;
  try {
    await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);
    canReadClipboard = true;
  } catch (e) {
    /* firefox/webkit: permission names unsupported */
  }
  const readClipboard = () =>
    canReadClipboard ? page.evaluate(() => navigator.clipboard.readText()) : Promise.resolve(null);
  const pageURL = URL.replace(/#.*$/, "");

  await reset();
  const linkEl = await page.evaluate((id) => {
    const a = document.querySelector("#" + CSS.escape(id) + " .block-link");
    return a && {
      isAnchor: a.tagName === "A",
      href: a.getAttribute("href"),
      label: a.getAttribute("aria-label"),
    };
  }, ID);
  check(
    "permalink is a real anchor with the block href",
    linkEl && linkEl.isAnchor && linkEl.href === "#" + ID,
    JSON.stringify(linkEl)
  );
  check("permalink label says it copies", /copy/i.test(linkEl ? linkEl.label : ""));

  // No selection: click selects + copies the whole-block URL.
  await page.hover("#" + ID); // reveal the button
  await page.click("#" + ID + " .block-link");
  r = await page.evaluate(() => ({
    hash: location.hash,
    block: document.querySelectorAll("pre.hl-block").length,
  }));
  check("permalink click selects the whole block", r.hash === "#" + ID && r.block === 1, r.hash);
  // the checkmark appears when the async clipboard write resolves
  const copiedShown = await page
    .waitForSelector(".block-link.copied", { timeout: 2000 })
    .then(() => true)
    .catch(() => false);
  check("permalink click shows copied feedback", copiedShown);
  let clip = await readClipboard();
  if (clip !== null) {
    check("clipboard holds the block URL", clip === pageURL + "#" + ID, clip);
  }
  await page.waitForTimeout(1700);
  r = await page.evaluate(() => !!document.querySelector(".block-link.copied"));
  check("copied feedback resets", r === false);

  // With lines selected in the block: click preserves + copies the selection.
  pos = await gutterPos(2);
  await page.mouse.click(pos.x, pos.y);
  await page.click("#" + ID + " .block-link");
  r = await state();
  check("permalink keeps the line selection", r.hl === 1 && /-L2$/.test(r.hash), r.hash);
  clip = await readClipboard();
  if (clip !== null) {
    check("clipboard holds the selection URL", clip === pageURL + r.hash, clip);
  }

  // A selection in ANOTHER block is not this block's: copy the whole block.
  const elsewhere = await page.evaluate((id) => {
    const p = Array.from(document.querySelectorAll("code.line-numbers")).find(
      (c) => c.parentElement.id !== id && c.querySelectorAll(".line").length >= 2
    );
    p.parentElement.scrollIntoView({ block: "center" });
    const r0 = p.querySelectorAll(".line-num")[0].getBoundingClientRect();
    return { x: r0.left + r0.width / 2, y: r0.top + r0.height / 2 };
  }, ID);
  await page.mouse.click(elsewhere.x, elsewhere.y); // select a line elsewhere
  await page.click("#" + ID + " .block-link");
  r = await state();
  check(
    "selection elsewhere: permalink retargets whole block",
    r.hash === "#" + ID,
    r.hash
  );
  await reset();

  // ---- hash restore on fresh load ----
  const restoreHash = `#${ID}-L3-L9`; // fixed range: the restore checks expect 7 lines
  const page2 = await browser.newPage({ viewport: { width: 1400, height: 950 } });
  await page2.goto(URL.replace(/#.*$/, "") + restoreHash, { waitUntil: "load" });
  await page2.waitForTimeout(3000);
  const restored = await page2.evaluate(() => {
    const el = document.querySelector(".line.hl");
    if (!el) return { hl: 0, visible: false };
    const r = el.getBoundingClientRect();
    return {
      hl: document.querySelectorAll(".line.hl").length,
      visible: r.top > 0 && r.bottom < window.innerHeight,
    };
  });
  check("hash restores highlight on fresh load", restored.hl === 7, `${restored.hl} lines`);
  check("restored selection scrolled into view", restored.visible);
  await page2.close();

  // ---- sticky pinning under horizontal scroll ----
  const page3 = await browser.newPage({ viewport: { width: 430, height: 900 } });
  await page3.goto(URL.replace(/#.*$/, ""), { waitUntil: "load" });
  await page3.waitForTimeout(3000);
  const sticky = await page3.evaluate(() => {
    let best = null,
      overflow = 0;
    for (const c of document.querySelectorAll("code.line-numbers")) {
      const o = c.scrollWidth - c.clientWidth;
      if (o > overflow) {
        overflow = o;
        best = c;
      }
    }
    if (!best) return { skipped: true };
    best.parentElement.scrollIntoView({ block: "center" });
    best.scrollLeft = 150;
    const cr = best.getBoundingClientRect();
    const nr = best.querySelector(".line-num").getBoundingClientRect();
    return { skipped: false, scrolled: best.scrollLeft, offset: Math.round(nr.left - cr.left) };
  });
  if (sticky.skipped) {
    check("sticky pin (skipped: no overflowing block at 430px)", true);
  } else {
    check("gutter pinned at left edge while scrolled", sticky.scrolled > 0 && sticky.offset === 0,
      JSON.stringify(sticky));
  }
  await page3.close();

  // ---- continued numbering (data-ln-start offsets), when present ---------
  // Only pages using `@codeblocks line_counter = :continue` have offset
  // blocks; on other pages this section reports itself skipped.
  const contBlocks = await page.evaluate(() =>
    Array.from(document.querySelectorAll(".code-lines[data-ln-start]")).map((w) => {
      const pre = w.closest("pre");
      // (getComputedStyle content returns the literal `counter(line)` —
      // browsers don't resolve counters there — so check the inline
      // counter-reset the digits render from instead.)
      const m = /line\s+(\d+)/.exec(w.style.counterReset || "");
      return {
        id: pre.id,
        start: parseInt(w.dataset.lnStart, 10),
        lines: w.querySelectorAll(".line").length,
        reset: m ? parseInt(m[1], 10) : null,
      };
    })
  );
  if (contBlocks.length === 0) {
    check("continued numbering (skipped: no data-ln-start blocks on page)", true);
  } else {
    // The CSS counter offset matches the declared start: the first gutter
    // digit renders as `reset + 1` == start.
    check(
      "continued blocks carry a matching counter offset",
      contBlocks.every((b) => b.reset === b.start - 1),
      JSON.stringify(contBlocks.map((b) => [b.start, b.reset]))
    );
    // Gutter click on a continued block puts the DISPLAYED number in the hash.
    const cb = contBlocks[0];
    await page.evaluate(() => history.replaceState(null, "", location.pathname));
    const cell = page.locator(`#${cb.id} .line .line-num`).first();
    await cell.click();
    const hash1 = await page.evaluate(() => location.hash);
    check(
      "gutter click uses displayed numbers in the hash",
      hash1 === `#${cb.id}-L${cb.start}`,
      `${hash1} (expected #${cb.id}-L${cb.start})`
    );
    // Hash restore maps the displayed number back to the right child line.
    const lastDisplayed = cb.start + cb.lines - 1;
    const hl = await page.evaluate(
      ([id, disp]) => {
        history.replaceState(null, "", `#${id}-L${disp}`);
        window.dispatchEvent(new HashChangeEvent("hashchange"));
        const lines = document.querySelectorAll(`#${id} .line`);
        return {
          hlIndex: Array.from(lines).findIndex((l) => l.classList.contains("hl")),
          hlCount: document.querySelectorAll(`#${id} .line.hl`).length,
        };
      },
      [cb.id, lastDisplayed]
    );
    check(
      "hash restore highlights the offset-mapped line",
      hl.hlCount === 1 && hl.hlIndex === cb.lines - 1,
      JSON.stringify(hl)
    );
    await page.evaluate(() => history.replaceState(null, "", location.pathname));
  }

  // ---- theme sweep: gutter bg must equal pre bg in all six themes ----
  const themes = ["documenter-light", "documenter-dark", "catppuccin-latte",
    "catppuccin-frappe", "catppuccin-macchiato", "catppuccin-mocha"];
  for (const t of themes) {
    const m = await page.evaluate(
      ([t, id]) => {
        localStorage.setItem("documenter-theme", t);
        if (typeof set_theme_from_local_storage === "function") set_theme_from_local_storage();
        const pre = document.getElementById(id);
        return (
          getComputedStyle(pre).backgroundColor ===
          getComputedStyle(pre.querySelector(".line-num")).backgroundColor
        );
      },
      [t, ID]
    );
    check(`theme ${t}: gutter bg matches pre bg`, m);
  }

  await browser.close();
  console.log(failures === 0 ? "\nALL CHECKS PASSED" : `\n${failures} CHECK(S) FAILED`);
  process.exit(failures === 0 ? 0 : 1);
})();
