# Galley: project plan

> Print your reading list as a magazine.

Galley is a Mac app that turns saved links into a printed magazine. You give it URLs. It extracts each article with its photos, lays everything out like a magazine (cover, contents page, numbered pages) and groups the articles into **editions** that you print at home: daily, weekly or monthly.

It is inspired by Offprint, a service that prints and posts a personal magazine each month. Galley runs locally instead, so it works anywhere with a printer, including places Offprint doesn't ship to. It starts as a personal tool and will be open-sourced once it's solid.

---

## 1. Goals and non-goals

### Goals
- **Paste a link, get a printed article.** Pages should look like a magazine, not a web page printed from a browser.
- **Editions are the main idea.** Articles collect into an open edition. Each edition has an issue number, a cover, a table of contents and continuous page numbers.
- **Local first.** Fetching, extraction, layout and printing all happen on your Mac. No server, no account, no cloud.
- **Works with your subscriptions.** Paywalled articles you legitimately have access to should print too.
- **Simple printing.** One-sided A4 by default, US Letter in US regions. The result is a stack of pages you can staple.
- **Open-source ready.** Clean structure, permissive licence, and themes that other people can write.

### Non-goals (for now)
- Two-sided or booklet printing. It's planned as a later setting, not built now (see §9).
- Bypassing paywalls. Galley will never ship tricks to get around a paywall (see §4).
- iOS or iPad apps, syncing between devices, or accounts.
- Offering a print-and-post service.

---

## 2. User experience

### 2.1 Main window
A standard three-column Mac layout (SwiftUI `NavigationSplitView`).

```
┌───────────────┬──────────────────────────┬─────────────────────────────────┐
│ ● Next Edition│  Galley No. 12           │                                 │
│               │  October 2026 · 9 stories│      ┌───────────────┐          │
│ EDITIONS      │                          │      │               │          │
│   No. 12  ◀   │  ☰ Cover                 │      │  page preview │          │
│   No. 11      │  ☰ Contents              │      │   (PDFKit)    │          │
│   No. 10      │  ☰ The Long Winter  p.3  │      │               │          │
│               │  ☰ On Maps          p.9  │      └───────────────┘          │
│ LIBRARY       │  ☰ ...                   │   ▢ ▢ ▢ ▢ ▢ ▢ ▢  (thumbnails)  │
│   All Articles│                          │                                 │
│   Failed      │  [+ Add Link]            │   [Theme ▾]  [Close & Print ⌘P] │
│               │                          │                                 │
│ SITES         │                          │                                 │
│   Logins      │                          │                                 │
└───────────────┴──────────────────────────┴─────────────────────────────────┘
```

- **Sidebar**
  - *Next Edition*: the open edition that new articles go into.
  - *Editions*: past issues, newest first.
  - *Library*: every article, plus the ones that failed to extract.
  - *Sites → Logins*: websites you've signed into (see §4).
- **Middle column**: the contents of the selected edition in order. Drag to reorder, right-click to remove, star one article to make it the cover story.
- **Detail pane**: a live page preview of the edition PDF with a thumbnail strip. Select an article in the middle column and the preview jumps to its first page.

### 2.2 Adding articles
- **⌘L or the + button**: a sheet with a URL field, pre-filled from the clipboard if it holds a URL.
- **Paste anywhere** in the window: if the clipboard holds URLs, add them. Pasting several lines adds several articles.
- **Drag and drop** a link from Safari or any other app onto the window.
- **Share extension** (milestone M5): *Share → Galley* from Safari or any other app.
- **Safari extension** (milestone M5): *Send to Galley* sends the page exactly as Safari shows it (see §4).

An added article appears straight away with a spinner and fills in as it's fetched: title, source, word count and first image. If it fails, it gets a clear status ("Needs login", "Couldn't find the article", "Timed out") and a **Fix…** button.

### 2.3 Editions and cadence
- The **cadence** is a setting: *Daily*, *Weekly* (you pick the day), *Monthly* (you pick the date) or *Manual*.
- There is always exactly one **open** edition, and new articles go into it.
- When the cadence period ends, the open edition **closes**: its contents are fixed, its PDF is rendered, and a new open edition starts. You get a notification: *"Galley No. 12 is ready to print, 9 stories, 64 pages."*
- **Close & Print** closes the open edition early whenever you like.
- An edition you've closed can be reopened for changes until you mark it **Printed**.
- **Page budget** (optional setting): a maximum page count, for example 60. If adding articles would go over it, the overflow moves to the next edition. The UI shows which articles are affected.

An edition moves through these states: `open → closed → printed`. You can go back from closed to open.

### 2.4 Printing
- **Print** opens the standard macOS print dialog with the edition PDF. Your printer, number of copies and page range all work as usual.
- **Export PDF…** saves the file, for example to take to a print shop.
- Printing is one-sided only for now. The layout never mirrors margins or pads the page count.

### 2.5 Settings
- **Paper**: A4 or US Letter. The default depends on your region.
- **Cadence**: daily, weekly, monthly or manual, plus the day or date.
- **Masthead**: the magazine's name on the cover. Defaults to "Galley"; you might use something like "The Ulaanbaatar Review".
- **Theme**: see §5.4.
- **Images**: full colour, greyscale (saves colour ink), or text only.
- **Links**: turn them into numbered endnotes, or print them as plain text.
- **Page budget**: none, or a maximum number of pages.
- Later: two-sided or booklet printing (§9).

### 2.6 Reading comfort on paper
- A short QR code at the end of each article links to the original, which helps with videos, interactive graphics and comments.
- Hyperlinks inside the text become small superscript numbers, listed as endnotes with the full URLs at the end of the article. This can be turned off.
- Embedded videos, tweets and interactive graphics become a box such as "▶ Video: *title*" with a QR code, instead of an empty gap.

---

## 3. How it works

```
URL ─► Fetcher ─► Extractor ─► Asset store ─► Edition builder ─► Renderer ─► PDF ─► Print
      (WKWebView)  (Readability) (local HTML    (HTML + theme)    (Paged.js    (PDFKit /
                                   + images)                        in WKWebView) NSPrintOperation)
```

### 3.1 Technology choices

| Concern | Choice | Why |
|---|---|---|
| UI | SwiftUI (macOS) | Native, and the fastest way to build a standard Mac layout |
| Storage | SwiftData | Built in, fits a small data model, no dependencies |
| Fetching | Offscreen `WKWebView` | A real browser, so JavaScript-heavy sites and your logins work |
| Extraction | Mozilla **Readability.js** (Apache-2.0) | Proven (it powers Firefox Reader View), runs inside WebKit |
| Layout | HTML + CSS themes, paginated by **Paged.js** (MIT) | Page numbers, running headers and contents page numbers from CSS; themes are easy to write |
| PDF | WebKit print to PDF, then PDFKit | No extra dependencies; PDFKit also handles preview and printing |
| QR codes | Core Image `CIQRCodeGenerator` | Built in |

**Minimum macOS**: to decide (see §12). I suggest **macOS 15** so more people can use the open-source release.

### 3.2 Project layout

```
Galley/
  Galley.xcodeproj
  Galley/                    # App target: SwiftUI views, app lifecycle, settings
  GalleyCore/                # Local Swift package, no UI:
    Models/                  #   SwiftData models
    Fetching/                #   WKWebView page loading, login sessions
    Extraction/              #   Readability bridge, clean-up, image download
    Editions/                #   cadence, closing, page budget
    Rendering/               #   HTML building, Paged.js run, PDF output
  Resources/
    js/readability.js
    js/paged.polyfill.js
    js/galley-prepare.js     # our own page clean-up before extraction
    themes/<name>/theme.css, cover.html, fonts/
  GalleyTests/               # extraction fixtures, rendering snapshots
  ShareExtension/            # milestone M5
  SafariExtension/           # milestone M5
```

Keeping `GalleyCore` separate from the UI means it can be tested on its own. It could also power a command-line tool later, such as `galley add <url>` or `galley render`.

### 3.3 Fetching
1. Create an offscreen `WKWebView` that uses the app's **persistent** website data store, so logins survive restarts (§4).
2. Load the URL. It counts as loaded when navigation finishes and the network has been quiet for about 1.5 seconds, with a hard limit of 30 seconds.
3. Run `galley-prepare.js` before extracting:
   - scroll through the page so lazy-loaded images load;
   - swap in the real image sources (`data-src`, `srcset`, `<picture>`), keeping the largest reasonable size;
   - expand collapsed "Read more" sections where that's safe;
   - remove cookie banners and newsletter pop-ups that could confuse Readability.
4. Several articles are fetched in parallel, at most 3 at once.

The user agent is a normal Safari one. Galley fetches pages the way you would read them, one page per link, with no crawling.

### 3.4 Extraction
1. Inject `readability.js` and run it on a copy of the page. It returns `title`, `byline`, `siteName`, `excerpt`, `publishedTime`, `lang` and `content` (the article HTML).
2. **Quality check.** If the extracted text is under about 250 words, or much shorter than the visible text on the page, mark the article **Needs attention** instead of printing a broken result.
3. **Clean-up** in Swift and JavaScript:
   - remove leftover share buttons, "related articles" lists and ads;
   - keep figures together with their captions;
   - turn embeds into placeholders (§2.6);
   - tidy the heading levels (the article title is the only top-level heading).
4. **Images**: download each one into the article's asset folder and point the HTML at the local copy.
   - Resize to about 300 dpi at the widest size a theme uses (about 2,000 px). This keeps PDFs small.
   - Convert formats that print badly to JPEG or PNG.
   - Skip tracking pixels and anything smaller than about 100 px.
5. **Metadata fallbacks**: if Readability misses something, use the page's OpenGraph or JSON-LD data (`og:image`, `article:published_time`, `author`). The `og:image` also becomes the cover image candidate.
6. Save `article.html`, `images/` and the metadata. **Galley prints only from the saved copy**, never from the live site, so an edition looks the same whenever you print it.

**Per-site fixes (later)**: a small, optional set of rules for particular sites, such as "the article body is in `.story-body`" or "remove `.paywall-teaser`". These cover cases where Readability gets a site wrong. Rules only fix extraction; they never remove a paywall.

### 3.5 Storage

```
~/Library/Application Support/Galley/
  Galley.store                # SwiftData database
  Articles/<uuid>/article.html
  Articles/<uuid>/images/*
  Editions/<number>/edition.pdf
```

- **Settings → Library → Show in Finder** opens this folder.
- **Export library** zips it up as a backup.

---

## 4. Paywalls and logins

Galley prints what you can read; it doesn't unlock what you can't.

### 4.1 Signing in inside the app (milestone M4)
- **Sites → Logins → Add Site…** opens a normal browser window inside Galley. You sign into the site there once.
- The login cookies are saved in Galley's own browser storage, so later fetches from that site arrive signed in.
- Galley **cannot** read Safari's or Chrome's cookies, because macOS apps are kept separate from each other. That's a good thing, and it's why the in-app sign-in exists.
- Each signed-in site is listed, with a **Sign out** button that deletes that site's cookies.

### 4.2 "Fix…" capture
When extraction fails or a paywall is detected, **Fix…** opens the article in the in-app browser window. You deal with whatever is in the way (a login, a cookie prompt, a "continue reading" click), then press **Capture**. Galley extracts the page as it is on screen at that moment.

### 4.3 The Safari extension (milestone M5)
*Send to Galley* runs in the Safari tab you're reading, where you're already signed in. It captures the finished page, including anything the site's scripts loaded, and passes it to the app. This is the most reliable path for tricky sites and for any subscription.

### 4.4 Detecting a paywall
Galley looks for common signs: `isAccessibleForFree: false` in the page's JSON-LD data, well-known paywall page elements, or a very short article next to a subscription prompt. If it finds one, the article is marked **Needs login** and shown with the site name, so you know to sign in or use Fix….

### 4.5 What Galley won't do
Galley won't use archive or cache sites to get around a paywall, pretend to be a search-engine crawler, block paywall scripts, or ship rules aimed at defeating a paywall. This is partly principle and partly practical: open-source projects that do these things attract takedown requests.

---

## 5. Layout and design

### 5.1 How rendering works
1. The **edition builder** writes one HTML document containing the cover, the contents page and each article in its own `<section>`.
2. It links the theme's CSS and fonts, plus `paged.polyfill.js`.
3. The document is loaded into an offscreen `WKWebView` that is allowed to read local files from the asset folders.
4. Paged.js splits the content into fixed-size pages. Galley waits for Paged.js to signal that it's finished.
5. The pages are exported to PDF (see the risk in §10.1):
   - **Plan A**: `NSPrintOperation` from the web view, with the page size set, zero margins, 100% scale, saved to a file.
   - **Plan B**: export each page's rectangle separately with `WKWebView.createPDF(configuration:)` and join the pages with PDFKit.
6. Galley checks that the PDF has the page count Paged.js reported, then saves it and shows the preview.

### 5.2 The page
- **Paper size**: A4 (210 × 297 mm) or Letter (8.5 × 11 in), set by CSS `@page { size: A4 }`.
- **Safe margins**: home printers can't print to the edge of the paper, so all content stays at least 10 mm from the edges. Nothing bleeds off the page, not even on the cover.
- **Same margins on every page**, as suits single-sided printing. Suggested: 18 mm top, 22 mm bottom, 20 mm left and right.
- **Running header**: the masthead and issue on the left ("Galley · No. 12 · October 2026"), the current article's title on the right. There's no header on the cover or on an article's first page.
- **Footer**: the page number at the bottom right, on every page except the cover.
- **Page numbers** run through the whole edition. The cover is page 1 but doesn't show a number; the contents page is page 2.

### 5.3 Parts of an edition
**Cover**
- The masthead (a large wordmark), the issue number and date, and the cover story's image inside the safe margins.
- Three or four "cover lines" (story headlines) with their page numbers.

**Contents**
- One entry per article: source, title, a one-line summary (the excerpt), byline, reading time and page number.
- The page numbers come from CSS (`target-counter(attr(href), page)`), so they are always correct.

**Articles**
- Each article starts on a new page.
- The opening has a kicker (the source name, such as "THE GUARDIAN"), the headline, a subheading (the excerpt), the byline, the date, the reading time and the lead image.
- The body text is set at about 10.5–11 pt serif, with hyphenation (`hyphens: auto` with a `lang` attribute) and a line length of roughly 65–75 characters.
- A drop cap on the first paragraph (depending on the theme).
- Figures have captions. Pull quotes are optional and can come from `<blockquote>`s.
- The ending has a ∎ mark, the endnotes, the source URL and the QR code.

**Back page** (optional): a colophon such as "Printed with Galley on 30 Sep 2026 · 9 stories · 64 pages".

### 5.4 Themes
A theme is a folder containing `theme.css`, `cover.html` (with placeholders), a `fonts/` folder and `theme.json` (name, author, licence, supported languages).

Planned first themes:
- **Classic**: single column, generous margins, serif (Source Serif 4). Readable and plain.
- **Broadsheet**: two columns on article pages, with a large headline across both. Depends on how well Paged.js handles columns (§10.2).
- **Notebook**: a narrow column of text with wide side margins for captions, figures and your own handwritten notes, in the style of Tufte's books.

**Fonts** are bundled with the app under the SIL Open Font License. They must support **Latin and Cyrillic** so that Mongolian and Russian articles print correctly; Source Serif 4, Literata, IBM Plex Sans and Inter all qualify. Galley uses the language the extractor detects to set hyphenation.

---

## 6. Data model (first draft)

```swift
@Model final class Article {
    var id: UUID
    var sourceURL: URL
    var canonicalURL: URL?
    var title: String
    var byline: String?
    var siteName: String?
    var excerpt: String?
    var publishedAt: Date?
    var language: String?
    var wordCount: Int
    var leadImagePath: String?        // relative to the article folder
    var status: ArticleStatus         // .queued .fetching .ready .needsLogin .needsAttention .failed
    var failureReason: String?
    var addedAt: Date
    var edition: Edition?
    var positionInEdition: Int
}

@Model final class Edition {
    var number: Int                   // No. 12
    var title: String?                // optional special title
    var periodStart: Date
    var periodEnd: Date
    var state: EditionState           // .open .closed .printed
    var coverArticle: Article?
    @Relationship var articles: [Article]
    var themeID: String
    var paper: PaperSize              // captured when the edition closes
    var pageCount: Int?
    var pdfPath: String?
    var closedAt: Date?
    var printedAt: Date?
}

@Model final class SiteLogin {        // only for display; the cookies live in WebKit's storage
    var host: String
    var addedAt: Date
    var lastUsedAt: Date?
}
```

Settings (cadence, paper, masthead, theme, image mode, link mode, page budget) are stored in `UserDefaults` / `@AppStorage`.

---

## 7. Scheduling editions

- Galley doesn't need to be running all the time. **At launch and every hour while it's open**, it checks whether the open edition's period has ended and closes it if so.
- Notifications that arrive exactly on time, even when the app is closed, are a later option. They would need a small background helper started at login (`SMAppService`). Most people will add links often enough that the check at launch is enough.
- Examples of how periods are calculated:
  - monthly on the 1st: the period runs from 1 October at 00:00 to 1 November at 00:00, local time;
  - weekly on Sunday: from one Sunday to the next;
  - daily: midnight to midnight.

---

## 8. Milestones

Each milestone ends with something you can use.

### M0 — Proof of concept (the riskiest part first)
- A minimal app: paste a URL, press Go, get a PDF.
- Covers fetching, Readability extraction, downloading images and rendering one article through Paged.js to a PDF with page numbers.
- **Done when**: 5 test articles (a news site, a Substack post, a Medium post, a long read with many images and a Mongolian-language site) each produce a readable, numbered A4 PDF with their images, and the PDF's page count matches what Paged.js reported.

### M1 — Library and editions
- The SwiftData models, the three-column UI, adding articles (sheet, paste, drag and drop) and fetch status.
- One open edition, manual Close, reordering, and the PDF preview.
- **Done when**: you can collect 10 articles over a few days, close the edition and print it.

### M2 — Making it a magazine
- The cover, the contents page with correct page numbers, running headers, the article opening design, drop caps and captions.
- Endnotes for links, QR codes and embed placeholders.
- The Classic theme is finished; greyscale mode.
- **Done when**: a printed edition looks like a magazine on paper, not a printed web page.

### M3 — Cadence and settings
- The cadence setting and closing editions automatically, notifications, and the page budget with overflow to the next edition.
- The settings window (paper, masthead, theme, images, links).
- **Done when**: set to weekly, editions close themselves and ask to be printed.

### M4 — Paywalls and difficult sites
- The in-app sign-in window and the logins list.
- Fix… capture, paywall detection, and the Needs-attention flow.
- **Done when**: articles from a site you subscribe to extract in full after you sign in once.

### M5 — Getting links in easily
- The share extension and the Safari extension ("Send to Galley").
- Importing a list of URLs from a text or CSV file.

### M6 — Open-source release
- MIT licence, NOTICE file (Readability is Apache-2.0, Paged.js is MIT, the fonts are OFL), README with screenshots, CONTRIBUTING, and a theme-writing guide.
- GitHub Actions to build and test.
- A signed, notarised DMG on GitHub Releases. That needs an Apple Developer account; otherwise people build it from source.
- Possibly a Homebrew cask later.

---

## 9. Later ideas
- **Two-sided printing**: mirrored margins, articles opening on right-hand pages, page numbers on the outer edge.
- **Booklet mode**: A5 booklets from A4 sheets, with pages reordered for folding and padded to a multiple of 4.
- **RSS sources**: follow a feed and add new posts to the next edition automatically, with filters.
- **Importing** from Instapaper, Readwise or browser bookmarks.
- **Command-line tool** (`galley add`, `galley render`) built on GalleyCore.
- **Optional AI touches** (off by default): writing summaries when a site has none, an editor's note for the edition, or translating an article before printing.
- **Crosswords or puzzles** as a filler on the last page.

---

## 10. Risks and open technical questions

1. **Turning WebKit + Paged.js output into PDF pages.** Paged.js is built for Chrome's PDF printing. WebKit's printing may add scaling, margins or page breaks of its own. *Mitigation*: test this first in M0, and keep plan B (exporting each page's rectangle and joining them with PDFKit) ready. Plan C would be Vivliostyle.js, a similar layout library.
2. **Multiple columns across pages in Paged.js** can be buggy. *Mitigation*: Classic stays single-column; Broadsheet is attempted only if M2 testing shows columns work.
3. **Extraction quality** varies a lot between sites. *Mitigation*: the quality check, Fix… capture, per-site rules later, and a set of test articles (§11).
4. **Performance** of a large edition (60+ pages, many images). *Mitigation*: shrink images when they're downloaded, render in the background, cache each article's HTML.
5. **Font coverage** for Mongolian Cyrillic (the letters Ө and Ү). *Mitigation*: check every bundled font against them.
6. **Legal and ethical questions around paywalls**: covered by the policy in §4.5, which also goes in the README.

---

## 11. Testing
- **Extraction fixtures**: saved HTML from 20–30 real pages across news sites, blogs, Substack, Medium, Wikipedia and Mongolian sites (for example ikon.mn and news.mn). Tests run Readability on them offline and compare the title, byline, word count and image count with expected values.
- **Rendering checks**: render a fixed test edition to PDF, then check the page count, the page numbers found in the text, and that the contents page numbers match where each article actually starts.
- **Edition tests**: calculating periods, closing on schedule, and pushing overflow to the next edition. These use an injected clock so they don't depend on the real date.
- **Checking on paper**: print one real edition at the end of each milestone. Some problems (text too small, images too dark, margins clipped) only show up on paper.

---

## 12. Decisions still to make
- **Minimum macOS version**: 15 (recommended) or only the latest?
- **First theme's look**: Classic single column (recommended) or two columns?
- **Default cadence**: monthly like Offprint, or weekly?
- **Where the code lives**: `yourname/galley` now, with the option of a `galley-press` organisation later.
- **Apple Developer account** for notarised releases: needed by M6, not before.

---

## 13. Settled so far
- **Name**: Galley. On GitHub the name is used by unrelated projects; the closest overlap is a small macOS PDF previewer (`munepi/Galley`). The `github.com/galley` handle is taken by an inactive food-company organisation; `galley-press` is free.
- **Paper**: A4 by default, Letter in US regions, printed one-sided. Two-sided printing is a later setting.
- **Platform**: a native Mac app (SwiftUI) for personal use first, then open source.
- **Approach**: WKWebView + Readability.js + Paged.js, with nothing ever printed straight from the live site.
- **Paywalls**: sign in inside the app, Fix… capture and the Safari extension. No bypassing.
