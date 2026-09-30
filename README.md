# Galley

**Print your reading list as a magazine.**

Galley is a Mac app that turns links into a printed magazine. Save articles as you
find them; each week (or day, or month) Galley gathers them into an **edition** with a
cover, a table of contents and numbered pages, laid out like a magazine and ready
for your printer.

It's inspired by Offprint, a service that prints and posts a personal
magazine every month. Galley does the same job on your own Mac, for your own printer,
wherever you live.

> Status: early (0.1). It works end to end for everyday reading. See [PLAN.md](PLAN.md)
> for where it's going.

## What it does

- **Paste a link, get a magazine article.** Galley opens the page in a real WebKit
  browser, pulls out the article with Mozilla's Readability (the engine behind
  Firefox Reader View), downloads the photos and saves a copy on your Mac.
- **Editions.** New articles go into the next edition. It closes on your schedule
  (weekly on Sunday by default; daily, monthly or manual in Settings), is laid out,
  and Galley tells you it's ready to print.
- **Magazine layout.** A cover with the lead story's photo, a contents page, page numbers
  and running headers, drop caps, captions, and links turned into numbered notes. Each
  article ends with a QR code back to the original.
- **Home printing.** A4 or US Letter, one-sided, with margins a home printer can handle.
  Colour, greyscale or text-only images.
- **Latin and Cyrillic.** The bundled fonts (Source Serif 4 and Inter) cover Mongolian and
  Russian as well as English and other European languages.
- **Paywalls, done honestly.** Sign in to sites you subscribe to in Galley's own browser,
  and fetched articles arrive in full. If a page gives trouble, open it there, deal with
  the pop-up, and press **Add to Galley**. Galley never tries to get around a paywall.

## Building

You need macOS 15 or later to run Galley and Xcode 26 or later to build it. The project is generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open Galley.xcodeproj
```

Then run the **Galley** scheme.

### The command line tool

`GalleyCore` is a Swift package with no UI, plus a small `galley-cli` for testing
extraction and layout:

```bash
cd GalleyCore
swift run galley-cli https://example.com/some-article --paper a4 --out ~/Desktop/test.pdf
```

Set `GALLEY_ROOT=/some/folder` to keep test files out of your real library. If your
checkout is in an iCloud Drive folder (Desktop or Documents with iCloud sync on), build
with `--scratch-path` somewhere outside it; iCloud's file attributes break code signing.

## How it works

```
URL → offscreen WKWebView → Readability.js → images saved locally
    → edition.html (cover + contents + articles, theme CSS)
    → Paged.js paginates in WebKit → each page captured to PDF → print
```

- `GalleyCore/` — fetching (`ArticleExtractor`), layout (`EditionRenderer`,
  `EditionHTML`), schedules (`Cadence`), and the bundled JavaScript, themes and fonts.
- `Galley/` — the SwiftUI app: SwiftData models, the library controller, and views.

Your library lives in `~/Library/Application Support/Galley`: one folder per article
(`article.html`, `meta.json`, `images/`) and one per edition (`edition.pdf`).

## Themes

A theme is a folder in `GalleyCore/Sources/GalleyCore/Resources/themes/` with a
`theme.css`, `fonts.css`, fonts and a `theme.json`. It uses ordinary CSS plus
[Paged Media](https://pagedjs.org/documentation/) features such as `@page`,
margin boxes, `string-set` and `target-counter`. Galley ships with **Classic**; more are
welcome.

## Licence

MIT. See [LICENSE](LICENSE). Third-party components and fonts are listed in [NOTICE](NOTICE).
