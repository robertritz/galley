// Galley render script. Loaded by edition.html next to paged.polyfill.js
// (with PagedConfig.auto = false). Swift calls galleyRender() and waits for it.

window.galleyRender = async function (opts) {
  // Links become numbered endnotes, so a reader on paper can still follow them.
  for (const article of document.querySelectorAll("article.story")) {
    const list = article.querySelector("ol.notes");
    let n = 0;
    for (const a of article.querySelectorAll(".body a[href]")) {
      const href = a.href;
      const text = a.textContent.trim();
      const isWebLink = /^https?:/.test(href);
      const textIsURL = /^(https?:\/\/|www\.)/i.test(text);
      if (opts.linkNotes && isWebLink && text && !textIsURL && !a.querySelector("img") && list) {
        n += 1;
        const sup = document.createElement("sup");
        sup.className = "note-ref";
        sup.textContent = n;
        a.after(sup);
        const li = document.createElement("li");
        li.textContent = href.replace(/^https?:\/\/(www\.)?/, "").replace(/\/$/, "");
        list.appendChild(li);
      }
      // Anchors carry no meaning on paper; keep their text only.
      a.replaceWith(...a.childNodes);
    }
    if (list && n === 0) list.closest(".notes-block")?.remove();
  }

  // Images that failed to download, and figures left with nothing to show.
  for (const img of document.querySelectorAll("img")) {
    if (!img.getAttribute("src")) img.remove();
  }
  for (const fig of document.querySelectorAll(".body figure")) {
    if (!fig.querySelector("img, svg, table, pre")) fig.remove();
  }

  // Tag the paragraph that gets the drop cap and the one that gets the end mark.
  for (const body of document.querySelectorAll("article.story .body")) {
    const paragraphs = [...body.querySelectorAll("p")].filter((p) => p.textContent.trim().length > 0);
    const first = paragraphs.find((p) => p.textContent.trim().length > 120 && !p.closest("figure, blockquote, aside, li"));
    if (first && /^[\p{L}\p{N}]/u.test(first.textContent.trim())) first.classList.add("first-paragraph");
    const last = paragraphs.reverse().find((p) => !p.closest("figure, aside"));
    if (last) last.classList.add("last-paragraph");
  }

  await document.fonts.ready;
  await Promise.all(
    [...document.images].map((img) => (img.complete ? null : img.decode().catch(() => img.remove())))
  );

  const twoColumns = document.body.classList.contains("columns-2");
  if (twoColumns) window.PagedPolyfill.registerHandlers(GalleyColumns);

  const t0 = performance.now();
  await window.PagedPolyfill.preview();
  const pagedMs = Math.round(performance.now() - t0);
  if (twoColumns) {
    mergeColumnPages();
    balanceLastSheets();
  }

  // Paged.js copies every element onto its page; wait for the copied images too,
  // or large ones (like the cover photo) are captured before they're painted.
  await Promise.all(
    [...document.querySelectorAll(".pagedjs_pages img")].map((img) => img.decode().catch(() => null))
  );

  // No running header on an article's first page or the contents page (below).
  const pages = [...document.querySelectorAll(".pagedjs_page")];
  for (const page of pages) {
    if (page.querySelector(".opener, .contents")) page.classList.add("galley-quiet-header");
  }

  const starts = {};
  for (const article of document.querySelectorAll("article.story[data-article]")) {
    const id = article.getAttribute("data-article");
    if (starts[id]) continue;
    const page = article.closest(".pagedjs_page");
    if (page) starts[id] = pages.indexOf(page) + 1;
  }
  // Page references on the cover and contents page. (Paged.js's target-counter
  // can't know about pages merged into columns, so Galley fills these in itself.)
  for (const ref of document.querySelectorAll(".page-ref[data-target]")) {
    ref.textContent = starts[ref.getAttribute("data-target")] || "";
  }

  // Lay pages out edge to edge so Swift can capture each one exactly.
  const style = document.createElement("style");
  style.textContent = `
    html, body { margin: 0 !important; padding: 0 !important; background: white !important; }
    .pagedjs_pages { display: block !important; margin: 0 !important; padding: 0 !important; }
    .pagedjs_page { margin: 0 !important; box-shadow: none !important; }
    .galley-quiet-header .pagedjs_margin-top > div { visibility: hidden; }
    /* Running header on one line: the edition line in full, the article title
       shortened with an ellipsis if it doesn't fit. */
    .pagedjs_margin-top { grid-template-columns: max-content 0 minmax(0, 1fr) !important; column-gap: 6mm; }
    .pagedjs_margin-top-left .pagedjs_margin-content { white-space: nowrap; }
    .pagedjs_margin-top-right, .pagedjs_margin-top-right .pagedjs_margin-content { min-width: 0; }
    .pagedjs_margin-top-right .pagedjs_margin-content {
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .pagedjs_page_content { position: relative; }
    .galley-right-column { position: absolute; left: calc(var(--col) + var(--gap)); width: var(--col); }
    .galley-balanced > .body, .galley-balanced > .source { width: auto; }
    .galley-balanced > .source { break-inside: avoid; }
    .galley-right-column::before {
      content: ""; position: absolute; top: 0; bottom: 0;
      left: calc(var(--gap) / -2); border-left: 0.4pt solid #d6d6d6;
    }
  `;
  document.head.appendChild(style);
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

  const rects = pages.map((p) => {
    const r = p.getBoundingClientRect();
    return { x: r.left + window.scrollX, y: r.top + window.scrollY, width: r.width, height: r.height };
  });

  return { pageCount: pages.length, rects, starts, documentHeight: document.documentElement.scrollHeight, pagedMs };
};

// ---------- Two columns ----------
//
// Paged.js can't carry CSS columns from page to page, so Galley composes them:
// article text is set in a single column-wide strip, Paged.js paginates it as
// usual, and then each following page of the same article is moved into the
// right-hand column of the page before it. The headline block stays full width.

const PagedHandler = window.Paged ? window.Paged.Handler : class {};

class GalleyColumns extends PagedHandler {
  constructor(chunker, polisher, caller) {
    super(chunker, polisher, caller);
    this.spacer = 0;
  }

  // The right-hand column on an article's first sheet starts below the headline,
  // so the page that will become it gets correspondingly less room.
  beforePageLayout(page) {
    if (this.spacer > 0 && page.area) {
      const height = page.area.getBoundingClientRect().height;
      page.area.style.marginTop = `${this.spacer}px`;
      page.area.style.height = `${height - this.spacer}px`;
      page.element.dataset.galleySpacer = String(this.spacer);
    }
    this.spacer = 0;
  }

  afterPageLayout(pageElement) {
    const opener = pageElement.querySelector(".opener");
    if (!opener || pageElement.querySelector("footer.source")) return;
    const area = pageElement.querySelector(".pagedjs_page_content");
    const gapBelow = parseFloat(getComputedStyle(opener).marginBottom) || 0;
    this.spacer = Math.ceil(opener.getBoundingClientRect().bottom + gapBelow - area.getBoundingClientRect().top);
  }
}

function storyOf(page) {
  const story = page.querySelector("article.story[data-article]");
  return story ? story.getAttribute("data-article") : null;
}

function mergeColumnPages() {
  const pages = [...document.querySelectorAll(".pagedjs_page")];
  for (let i = 0; i < pages.length; i++) {
    const left = pages[i];
    const right = pages[i + 1];
    const id = storyOf(left);
    if (!id || !right || storyOf(right) !== id || right.querySelector(".opener")) continue;
    const content = right.querySelector(".pagedjs_page_content");
    const column = document.createElement("div");
    column.className = "galley-right-column";
    column.style.top = `${right.dataset.galleySpacer || 0}px`;
    while (content.firstChild) column.appendChild(content.firstChild);
    left.querySelector(".pagedjs_page_content").appendChild(column);
    right.remove();
    i += 1;
  }
}

// An article's last sheet usually has a full left column and a short (or empty)
// right one. Re-flow that sheet's text into two balanced CSS columns. It already
// fits on one sheet, so no page break is involved and balancing is safe; if it
// somehow comes out taller than the page, the original layout is put back.
function balanceLastSheets() {
  const lastSheet = new Map();
  for (const page of document.querySelectorAll(".pagedjs_page")) {
    const id = storyOf(page);
    if (id) lastSheet.set(id, page);
  }
  for (const page of lastSheet.values()) {
    const area = page.querySelector(".pagedjs_page_content");
    const story = area.querySelector(":scope > div > article.story");
    const right = area.querySelector(".galley-right-column");
    if (!story) continue;
    const parts = [...story.querySelectorAll(":scope > .body, :scope > footer.source")];
    const rightParts = right ? [...right.querySelectorAll("article.story > .body, article.story > footer.source")] : [];
    const all = [...parts, ...rightParts];
    if (all.length === 0) continue;

    // Paged.js makes the page area a multi-column box to measure overflow; nested
    // inside it, our columns can't balance. Layout is finished, so switch it off.
    area.style.columns = "auto";
    area.style.columnWidth = "auto";

    // Height of the text as one column (it's already set at column width).
    const outer = (el) => {
      const cs = getComputedStyle(el);
      return el.getBoundingClientRect().height + parseFloat(cs.marginTop) + parseFloat(cs.marginBottom);
    };
    const total = all.reduce((sum, el) => sum + outer(el), 0);

    // Remember where everything was, in case balancing doesn't fit.
    const homes = all.map((el) => ({ el, parent: el.parentNode, next: el.nextSibling }));
    const balanced = document.createElement("div");
    balanced.className = "galley-balanced";
    // Styled inline: this runs before the stylesheet added at the end of galleyRender.
    Object.assign(balanced.style, {
      width: "calc(2 * var(--col) + var(--gap))",
      columnCount: "2",
      columnGap: "var(--gap)",
      columnFill: "auto",
      columnRule: "0.4pt solid #d6d6d6",
    });
    story.appendChild(balanced);
    for (const el of all) balanced.appendChild(el);
    if (right) right.style.display = "none";

    // Start at half the text height and grow until it all fits in two columns
    // (unbreakable blocks such as pictures or the QR code need a little slack).
    const available = area.getBoundingClientRect().bottom - balanced.getBoundingClientRect().top;
    let height = Math.ceil(total / 2);
    let fits = false;
    while (height <= available) {
      balanced.style.height = `${height}px`;
      // Content that doesn't fit spills into a third column to the right.
      const edge = balanced.getBoundingClientRect().right;
      const spills = [...balanced.querySelectorAll("*")].some((el) => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.left > edge - 2;
      });
      if (!spills) { fits = true; break; }
      height += 6;
    }
    if (fits) {
      if (right) right.remove();
    } else {
      for (const { el, parent, next } of homes.reverse()) parent.insertBefore(el, next);
      balanced.remove();
      if (right) right.style.display = "";
    }
  }
}
