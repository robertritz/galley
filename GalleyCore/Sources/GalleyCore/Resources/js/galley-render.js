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

  await window.PagedPolyfill.preview();

  // Paged.js copies every element onto its page; wait for the copied images too,
  // or large ones (like the cover photo) are captured before they're painted.
  await Promise.all(
    [...document.querySelectorAll(".pagedjs_pages img")].map((img) => img.decode().catch(() => null))
  );

  // No running header on an article's first page or the contents page.
  const pages = [...document.querySelectorAll(".pagedjs_page")];
  for (const page of pages) {
    if (page.querySelector(".opener, .contents")) page.classList.add("galley-quiet-header");
  }

  const starts = {};
  for (const article of document.querySelectorAll("article.story[data-id]")) {
    const id = article.getAttribute("data-id");
    if (starts[id]) continue;
    const page = article.closest(".pagedjs_page");
    if (page) starts[id] = pages.indexOf(page) + 1;
  }

  // Lay pages out edge to edge so Swift can capture each one exactly.
  const style = document.createElement("style");
  style.textContent = `
    html, body { margin: 0 !important; padding: 0 !important; background: white !important; }
    .pagedjs_pages { display: block !important; margin: 0 !important; padding: 0 !important; }
    .pagedjs_page { margin: 0 !important; box-shadow: none !important; }
    .galley-quiet-header .pagedjs_margin-top > div { visibility: hidden; }
  `;
  document.head.appendChild(style);
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

  const rects = pages.map((p) => {
    const r = p.getBoundingClientRect();
    return { x: r.left + window.scrollX, y: r.top + window.scrollY, width: r.width, height: r.height };
  });

  return { pageCount: pages.length, rects, starts, documentHeight: document.documentElement.scrollHeight };
};
