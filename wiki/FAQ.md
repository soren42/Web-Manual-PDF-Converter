# FAQ

## General

### What kinds of sites work best with webmanual?

Sites that serve pre-rendered HTML -- static documentation generators (Sphinx, MkDocs, Docusaurus with SSR, Hugo, Jekyll, GitBook), server-rendered pages, and plain HTML sites. If you can `curl` a page and see the content in the HTML source, it will work.

### Does it work with JavaScript-rendered (SPA) sites?

No. `webmanual` fetches raw HTML with curl. Sites that rely on client-side JavaScript to render content will produce blank or skeleton-only PDFs. See [Troubleshooting](Troubleshooting.md) for how to identify these sites.

### Can I generate a manual from a site that requires authentication?

Not directly. The script uses `curl` without cookies or authentication headers. If you need to capture authenticated content, you would need to modify the `fetch_url` and `is_html_content` functions to include the appropriate credentials (e.g., cookie jar, bearer token).

### How long does it take?

Roughly 3--5 seconds per page (HTTP requests + WeasyPrint rendering). OCR adds additional time depending on the total PDF page count. A 50-page crawl typically completes in 3--5 minutes. Use `--no-ocr` to cut the final step.

---

## Crawling

### How does the crawler decide which pages to include?

It uses breadth-first search starting from the seed URL, following only links that share the same scheme, host, and path prefix. See [Scope Detection](Scope-Detection.md) for full details.

### Will it crawl the entire internet?

No. The scope prefix restricts the crawler to a specific section of a single domain. Additionally, the `-M`/`--max-pages` limit (default: 50) caps the total number of pages, and `-D`/`--depth` (default: 2) limits how many link-hops from the seed URL the crawler will follow.

### Does it respect robots.txt?

No. `webmanual` does not parse or honor `robots.txt`. Use responsibly and consider the target site's terms of service.

### Does it handle pagination or "load more" buttons?

Only if pagination is implemented as standard `<a href>` links in the HTML. JavaScript-driven pagination, infinite scroll, or AJAX-loaded content will not be followed.

### What about duplicate content?

The crawler tracks visited URLs in an associative array and never visits the same URL twice. URLs are normalized (fragments stripped, `index.html` collapsed) to reduce duplicates. However, if the same content is served at two different URLs, both will be included.

### My crawl only fetches the seed URL and stops. Why?

This usually means the site renders its navigation via JavaScript -- the article body itself may be in the HTML, but the related-article links and side navigation are injected client-side. `curl` can't see those links, so the BFS has nothing to follow.

This is common on Salesforce Knowledge / Experience Cloud sites (URL pattern `/s/article/...`), Help Scout Docs, Zendesk Help Center, and similar SaaS knowledge bases.

**Workaround**: Use `-S`/`--sitemap` to seed the crawl queue directly from the site's `sitemap.xml`. Most knowledge bases publish one. The sitemap-index format is supported (sub-sitemaps are followed recursively), and all URLs are still filtered through the normal scope check.

```zsh
./webmanual.zsh -S https://support.example.com/s/sitemap.xml \
                https://support.example.com/s/article/getting-started
```

The seed URL is still required (it determines the scope prefix and serves as the entry point); the sitemap supplements it with additional URLs that BFS would otherwise miss.

---

## Output

### Why do some sites render cleanly while others have navigation artifacts?

`webmanual` automatically strips overlay elements (hamburger menus, feedback buttons, cookie banners, fixed navbars) using a two-layer approach: HTML DOM stripping followed by a CSS safety net. The HTML cleaner analyzes each page's embedded CSS to detect `position: fixed/sticky` elements and also matches common overlay class-name patterns. Most documentation sites are handled automatically. If an overlay survives, see [Troubleshooting](Troubleshooting.md) for how to add site-specific rules.

### What page size does it use?

US Letter (8.5" x 11"). This is set in the print stylesheet's `@page` rule. To change it, modify the CSS in the `main()` function -- e.g., `size: A4;` for A4 paper.

### Can I get one PDF page per webpage?

Each webpage becomes its own section in the PDF, starting on a new page. However, a single webpage may span multiple PDF pages depending on its content length. There is no single-page-per-webpage mode.

### Why does the output PDF have more pages than webpages crawled?

The PDF includes a cover page and a table of contents in addition to the rendered webpages. Each webpage may also span multiple PDF pages depending on content length.

### Can I customize the cover page or table of contents?

Currently, these are generated from HTML templates embedded in the script (`generate_cover_page` and `generate_toc_page` functions). Edit these functions to customize the appearance.

### Is the text in the PDF selectable/searchable?

Yes. WeasyPrint produces PDFs with real text (not rasterized). The OCR step (via OCRmyPDF) adds a text layer to any image-based content. Use `--no-ocr` if you only need the WeasyPrint text layer.

---

## Technical

### Why ZSH instead of Bash?

The script uses ZSH-specific features: `zparseopts` for argument parsing, associative arrays with `typeset -A`, `TRAP*` named functions for signal handling, `emulate -L zsh` for local option scoping, and `zmodload` for datetime formatting. These features simplify the implementation and improve safety compared to Bash equivalents.

### Why not use a headless browser (Puppeteer, Playwright)?

WeasyPrint is lightweight, installs via pip, and produces high-quality print PDFs with proper `@page` support. Headless browsers are heavier dependencies, slower, and their PDF output is optimized for screen rendering rather than print layout. The tradeoff is that WeasyPrint cannot execute JavaScript.

### Can I use this as a library / source it into another script?

Yes. The script includes a source guard at the bottom. When sourced (rather than executed), it only defines functions without running `_main`. You can then call individual functions like `compute_scope`, `extract_links`, or `render_page_to_pdf` from your own script.

### Does it handle HTTPS certificate errors?

No. curl's default behavior is to reject invalid certificates. If you need to accept self-signed certificates (e.g., for internal documentation), you would need to add `--insecure` to the curl calls in `fetch_url` and `is_html_content`.
