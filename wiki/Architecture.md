# Architecture

## Overview

`webmanual` is a single-file ZSH script built on a structured template. It orchestrates several external tools through a six-stage pipeline: **crawl, clean, render, assemble, OCR, output**.

## Pipeline

```
                    ┌──────────────────────────────────────────────────┐
                    │                   webmanual.zsh                  │
                    └──────────────────────────────────────────────────┘
                                          │
         ┌────────────────────────────────┼────────────────────────────────┐
         ▼                                ▼                                ▼
   ┌──────────┐   ┌──────────────┐  ┌──────────────┐              ┌────────────┐
   │  Stage 1 │   │   Stage 2    │  │   Stage 3    │              │  Stage 4   │
   │  Crawl   │   │   Clean      │  │   Render     │              │  Assemble  │
   │          │   │              │  │              │              │            │
   │  curl    │──>│  html_cleaner│─>│  WeasyPrint  │──── PDFs ──>│  pdfunite  │
   │  python3 │   │  .py         │  │  + print CSS │              │  + cover   │
   │  (links) │   │              │  │              │              │  + TOC     │
   └──────────┘   └──────────────┘  └──────────────┘              └─────┬──────┘
                                                                        │
                                                                  ┌─────▼──────┐
                                                                  │  Stage 5   │
                                                                  │  OCR       │
                                                                  │            │
                                                                  │  OCRmyPDF  │
                                                                  └─────┬──────┘
                                                                        │
                                                                  ┌─────▼──────┐
                                                                  │  Stage 6   │
                                                                  │  Output    │
                                                                  │            │
                                                                  │  cp → PDF  │
                                                                  └────────────┘
```

## Stage Details

### Stage 1: Crawl (BFS)

The crawler uses **breadth-first search** with a file-based queue (`$work_dir/queue`). Each entry is a tab-separated `URL\tdepth` pair.

For each URL dequeued:
1. **Dedup check** -- Skip if the URL is already in the `visited` associative array.
2. **Content-type check** -- An HTTP HEAD request via `curl` verifies the response is `text/html`. Non-HTML resources (images, PDFs, archives) are skipped.
3. **Fetch** -- The page is downloaded to `$work_dir/page_N.html`.
4. **Link extraction** -- An inline Python script using `html.parser.HTMLParser` extracts all `<a href>` attributes, resolves them against the page's base URL, strips fragments, and normalizes `index.html` paths.
5. **Scope filter** -- Each extracted link is checked against the scope prefix. Only in-scope links are enqueued (at `depth + 1`).

The crawl terminates when the queue is empty, `MAX_DEPTH` is reached, or `MAX_PAGES` pages have been fetched.

### Stage 2: Clean (HTML Preprocessing)

Before rendering, each fetched HTML file is processed by `html_cleaner.py` -- a Python script written once to the work directory and reused for every page. The cleaner removes UI chrome that would otherwise appear as artifacts in the PDF.

The cleaner operates in two phases:

**Phase 1 -- CSS analysis.** All `<style>` blocks in the HTML are parsed. CSS rules containing `position: fixed` or `position: sticky` are identified, and the class names and IDs from their selectors are collected. These are the elements the site's own stylesheet pins to the viewport -- exactly the overlays that obscure content in a static PDF.

**Phase 2 -- Pattern matching.** A set of site-agnostic heuristics catches common overlay elements that may not be styled via embedded CSS (e.g., styles loaded from external sheets or applied by JavaScript). Patterns include:

- **Class names**: hamburger, burger, feedback, cornerButton, sidebar, cookie-banner, cookie-consent, overlay, modal, toast, popup, banner, skip-link
- **IDs**: navBtn, searchBtn, ot-sdk-btn, cookie*, feedback*
- **ARIA roles**: `navigation`, `banner`
- **aria-label keywords**: navigation, menu, sidebar, feedback
- **Inline styles**: `position: fixed`, `position: sticky`

Any element matching Phase 1 or Phase 2 -- along with all of its children -- is stripped from the DOM. A `<base href>` tag is injected pointing to the original URL so that WeasyPrint can still resolve relative image, stylesheet, and font references from the local file.

### Stage 3: Render

Each cleaned HTML file is rendered to an individual PDF by **WeasyPrint**. The renderer:
- Reads the local cleaned HTML file (not the remote URL).
- Uses `-u <base_url>` so WeasyPrint resolves relative resources against the original URL.
- Applies a print stylesheet (see [Print Stylesheet](Print-Stylesheet.md)) as a CSS safety net for any overlay patterns not caught by the HTML cleaner.
- Uses Letter page size with 1.5cm margins.

### Stage 4: Assemble

Two additional PDFs are generated before merging:

- **Cover page** -- An HTML page rendered by WeasyPrint displaying the manual title (from the first page's `<title>`), seed URL, and generation date.
- **Table of contents** -- An HTML ordered list of all successfully rendered pages with titles and URLs.

All PDFs are concatenated in order using `pdfunite`:
```
cover.pdf + toc.pdf + render_0.pdf + render_1.pdf + ... + render_N.pdf
```

### Stage 5: OCR

The merged PDF is passed through `ocrmypdf --skip-text --optimize 1`. The `--skip-text` flag preserves existing text layers (from WeasyPrint) and only OCRs image-based content. This step is optional (`--no-ocr`).

### Stage 6: Output

The final PDF is copied from the temp directory to the user-specified (or auto-generated) output path. The temp directory is cleaned up by the `TRAPEXIT` handler.

## Script Structure

The script follows a template with these major sections:

| Section | Purpose |
|---------|---------|
| Shell options | Strict mode (`ERR_EXIT`, `NO_UNSET`, `PIPE_FAIL`) and safety settings |
| Constants | Script metadata, exit codes, verbosity levels |
| Global variables | Mutable state: verbosity, dry-run flag, temp tracking, crawl settings |
| Logging | Timestamped, colored, leveled logging (all to stderr) |
| Error handling | `TRAPZERR`, `TRAPEXIT`, `TRAPINT`/`TERM`/`HUP` handlers |
| Dependency validation | `require_binary` / `optional_binary` checks at startup |
| Argument parsing | `zparseopts`-based option processing |
| URL utilities | Python-backed URL parsing, normalization, scope computation |
| Crawling | BFS crawler, link extractor, content-type checker |
| HTML cleaning | Overlay/chrome stripping via `html_cleaner.py` |
| PDF generation | WeasyPrint rendering, cover/TOC generation |
| Main logic | Pipeline orchestration |
| Entry point | Source guard, initialization, argument flow |

## Design Decisions

**Why ZSH?** The project template targets ZSH specifically, using features like `zparseopts`, associative arrays, `emulate -L zsh`, `TRAP*` functions, and `zmodload`. This is not a POSIX sh script.

**Why Python for link extraction and HTML cleaning?** ZSH has no built-in HTML parser. Python's `html.parser` from the standard library is reliable, handles malformed HTML gracefully, and properly resolves relative URLs via `urllib.parse`. The Python invocations are small scripts with no external package dependencies (only stdlib).

**Why strip overlays from the DOM instead of just hiding them with CSS?** Many overlay elements (hamburger menus, feedback buttons, cookie banners) are positioned via external stylesheets or JavaScript -- not via inline styles or embedded `<style>` blocks. A CSS-only approach using `display: none` requires knowing every possible class name across every documentation framework. DOM stripping is more reliable: it analyzes the page's own CSS to find fixed/sticky selectors, combines that with pattern-based heuristics, and removes the elements entirely. A CSS safety net still catches edge cases.

**Why render local HTML instead of passing the URL to WeasyPrint?** Rendering from the already-fetched local file eliminates a redundant HTTP request per page and -- critically -- ensures the HTML cleaning step cannot be bypassed. The `-u <base_url>` flag tells WeasyPrint where to resolve relative resource paths.

**Why WeasyPrint over wkhtmltopdf?** WeasyPrint is actively maintained, produces high-quality output, supports modern CSS (including `@page` rules), and installs cleanly via pip.

**Why file-based queue instead of a ZSH array?** The BFS queue is stored in a file to keep the crawl loop simple and to avoid issues with large arrays in strict mode. Reading/writing lines to a file is straightforward and debuggable.

**Why are all logs on stderr?** Functions like `create_temp_dir` return values via stdout. Logging to stdout would contaminate captured output in `$(...)` subshells. Stderr is the correct channel for diagnostic output.
