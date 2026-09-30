// Galley extraction script.
//
// Runs inside the loaded page (in an isolated content world) after readability.js
// has been evaluated. Galley calls it with callAsyncJavaScript, so the body of
// this file is the body of an async function and its return value is sent back
// to Swift as a dictionary.

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const abs = (u) => {
  try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
};

// 1. Scroll through the page so lazy-loaded images and sections appear.
{
  const step = Math.max(400, window.innerHeight * 0.9);
  const limit = Math.min(document.documentElement.scrollHeight, 60000);
  for (let y = 0; y < limit; y += step) {
    window.scrollTo(0, y);
    await sleep(80);
  }
  window.scrollTo(0, 0);
  await sleep(150);
}

// 2. Pick a real image source for every <img>: undo lazy-loading placeholders and
//    choose the largest reasonable candidate from srcset / <picture>.
function bestFromSrcset(srcset) {
  if (!srcset) return null;
  let best = null, bestScore = -1;
  for (const part of srcset.split(/,\s+(?=\S)/)) {
    const [url, desc] = part.trim().split(/\s+/);
    if (!url) continue;
    let score = 1;
    if (desc && desc.endsWith("w")) score = parseInt(desc, 10);
    else if (desc && desc.endsWith("x")) score = parseFloat(desc) * 1000;
    if (score > 2600) score = 1; // too big to be worth downloading; prefer a smaller one
    if (score > bestScore) { best = url; bestScore = score; }
  }
  return best;
}

const lazyAttrs = ["data-src", "data-lazy-src", "data-original", "data-url", "data-hi-res-src", "data-full-src"];
for (const img of document.querySelectorAll("img")) {
  const current = img.getAttribute("src") || "";
  const looksPlaceholder = !current || current.startsWith("data:") || /blank|placeholder|spacer|transparent/i.test(current);
  let chosen = null;

  const picture = img.closest("picture");
  if (picture) {
    for (const source of picture.querySelectorAll("source")) {
      const type = source.getAttribute("type") || "";
      if (type && !/jpe?g|png|webp|avif|gif/.test(type)) continue;
      chosen = bestFromSrcset(source.getAttribute("srcset") || source.getAttribute("data-srcset"));
      if (chosen) break;
    }
  }
  chosen = chosen || bestFromSrcset(img.getAttribute("srcset") || img.getAttribute("data-srcset"));
  if (!chosen && looksPlaceholder) {
    for (const a of lazyAttrs) {
      if (img.getAttribute(a)) { chosen = img.getAttribute(a); break; }
    }
  }
  if (chosen) img.setAttribute("src", abs(chosen));
  else if (current && !current.startsWith("data:")) img.setAttribute("src", abs(current));
  img.removeAttribute("srcset");
  img.removeAttribute("sizes");
  img.removeAttribute("loading");
}

// 3. Metadata that Readability does not cover.
function meta(...names) {
  for (const n of names) {
    const el = document.querySelector(`meta[property="${n}"], meta[name="${n}"]`);
    if (el && el.content) return el.content.trim();
  }
  return null;
}

let jsonld = [];
for (const s of document.querySelectorAll('script[type="application/ld+json"]')) {
  try {
    const data = JSON.parse(s.textContent);
    const items = Array.isArray(data) ? data : (data["@graph"] || [data]);
    jsonld.push(...items.filter((x) => x && typeof x === "object"));
  } catch (e) { /* ignore malformed JSON-LD */ }
}
const ldArticle = jsonld.find((x) => /Article|BlogPosting|Report/.test([].concat(x["@type"] || []).join(" ")));
const notFree = jsonld.some((x) => x.isAccessibleForFree === false || x.isAccessibleForFree === "False" || x.isAccessibleForFree === "false");

function ldAuthor(a) {
  if (!a) return null;
  const list = [].concat(a).map((p) => (typeof p === "string" ? p : p && p.name)).filter(Boolean);
  return list.length ? list.join(", ") : null;
}
function ldImage(i) {
  if (!i) return null;
  const first = [].concat(i)[0];
  return typeof first === "string" ? first : first && (first.url || first.contentUrl);
}

const visibleTextLength = (document.body && document.body.innerText || "").length;

// 4. Readability on a copy of the page.
const clone = document.cloneNode(true);

// Clutter that sites mark as not meant for print or reading: maintenance notices,
// edit links, citation markers, navigation boxes (Wikipedia and MediaWiki use
// these conventions; "noprint" is common elsewhere too).
for (const el of clone.querySelectorAll([
  ".noprint", ".mw-editsection", ".ambox", ".hatnote", ".navbox", ".vertical-navbox",
  ".sistersitebox", ".mw-empty-elt", "sup.reference", ".mw-cite-backlink", ".shortdescription",
  "[role=navigation]", "[aria-hidden=true]:not(img)", ".visually-hidden", ".sr-only",
].join(","))) el.remove();
const parsed = new Readability(clone, { keepClasses: false, charThreshold: 400 }).parse();
if (!parsed || !parsed.content) {
  return { ok: false, reason: "Couldn't find the article on this page.", paywalled: notFree, visibleTextLength };
}

// 5. Clean the article HTML for print.
const root = document.createElement("div");
root.innerHTML = parsed.content;

const title = (parsed.title || meta("og:title") || document.title || "").trim();

// Readability often repeats the headline as the first heading.
const norm = (s) => (s || "").replace(/\s+/g, " ").trim().toLowerCase();
const firstHeading = root.querySelector("h1, h2");
if (firstHeading && norm(firstHeading.textContent) === norm(title)) firstHeading.remove();
for (const h of root.querySelectorAll("h1")) {
  const h2 = document.createElement("h2");
  h2.innerHTML = h.innerHTML;
  h.replaceWith(h2);
}

// Embedded media cannot print; replace with a labelled box linking to the original.
function placeholder(kind, label, href) {
  const aside = document.createElement("aside");
  aside.className = "galley-embed";
  aside.setAttribute("data-kind", kind);
  if (href) aside.setAttribute("data-href", href);
  aside.textContent = label;
  return aside;
}
for (const el of root.querySelectorAll("iframe, video, audio, embed, object")) {
  const src = abs(el.getAttribute("src") || el.getAttribute("data") || (el.querySelector("source") || {}).src || "");
  const tag = el.tagName.toLowerCase();
  let kind = tag === "audio" ? "Audio" : "Video";
  if (src && /twitter|x\.com|instagram|facebook|tiktok|bsky/.test(src)) kind = "Post";
  else if (tag === "iframe" && src && !/youtube|youtu\.be|vimeo|dailymotion/.test(src)) kind = "Interactive";
  el.replaceWith(placeholder(kind, el.getAttribute("title") || kind, src || location.href));
}
for (const el of root.querySelectorAll("script, style, noscript, form, input, button, select, textarea, svg[aria-hidden=true]")) el.remove();

// Collect images. Swift downloads them and swaps the galley-img:N placeholders
// for local file names.
const images = [];
for (const img of root.querySelectorAll("img")) {
  const src = img.getAttribute("src");
  const w = parseInt(img.getAttribute("width") || "0", 10);
  const h = parseInt(img.getAttribute("height") || "0", 10);
  if (!src || src.startsWith("data:") || (w && w < 80) || (h && h < 80)) {
    const fig = img.closest("figure");
    (fig && fig.querySelectorAll("img").length === 1 ? fig : img).remove();
    continue;
  }
  const index = images.length;
  images.push(abs(src));
  for (const a of [...img.attributes]) {
    if (!["alt", "title"].includes(a.name)) img.removeAttribute(a.name);
  }
  img.setAttribute("src", `galley-img:${index}`);
}
for (const s of root.querySelectorAll("picture source")) s.remove();

// Line breaks at the start or end of a paragraph only add blank lines on paper.
for (const br of root.querySelectorAll("p > br:first-child, p > br:last-child")) br.remove();

// Drop paragraphs left empty by the clean-up.
for (const p of root.querySelectorAll("p, div, span")) {
  if (!p.textContent.trim() && !p.querySelector("img, aside, br, hr")) p.remove();
}

const text = root.textContent || "";
const wordCount = (text.match(/\S+/g) || []).length;

return {
  ok: true,
  title,
  byline: (parsed.byline || ldAuthor(ldArticle && ldArticle.author) || meta("author", "article:author") || "").trim() || null,
  siteName: (parsed.siteName || meta("og:site_name", "application-name") || location.hostname.replace(/^www\./, "")).trim(),
  excerpt: (parsed.excerpt || meta("og:description", "description") || "").trim() || null,
  publishedTime: parsed.publishedTime || (ldArticle && ldArticle.datePublished) || meta("article:published_time", "date") || null,
  lang: parsed.lang || document.documentElement.lang || null,
  dir: parsed.dir || null,
  leadImage: abs(meta("og:image", "twitter:image") || ldImage(ldArticle && ldArticle.image) || "") || null,
  canonicalURL: abs((document.querySelector('link[rel="canonical"]') || {}).href || location.href),
  html: root.innerHTML,
  images,
  wordCount,
  paywalled: notFree,
  visibleTextLength,
};
