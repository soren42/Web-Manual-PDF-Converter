# Print Stylesheet

`webmanual` uses a two-layer approach to remove UI chrome from rendered PDFs:

1. **HTML cleaner** (primary) -- Strips overlay elements from the DOM before rendering. See [Architecture](Architecture.md) for details.
2. **Print stylesheet** (safety net) -- CSS rules that catch any patterns the HTML cleaner misses.

This page documents the CSS safety-net layer.

## How the Layers Work Together

The HTML cleaner runs first, analyzing each page's embedded `<style>` blocks to find `position: fixed/sticky` elements, then pattern-matching common overlay class names and ARIA roles. Matching elements are removed from the HTML entirely.

The print stylesheet runs second, applied by WeasyPrint during rendering. It serves as a fallback for elements styled by external CSS (which the HTML cleaner cannot parse) or patterns not covered by the cleaner's heuristics. Because the cleaner handles most overlays, the stylesheet focuses on broad attribute selectors and print layout.

## Default Stylesheet

The built-in print stylesheet is created once per run at `$work_dir/print.css` and applied to every page via `weasyprint -s`:

```css
@page {
    size: Letter;
    margin: 1.5cm;
}
body {
    font-size: 11pt;
    line-height: 1.4;
    max-width: 100%;
}
/* CSS safety net: catch any fixed/sticky elements the HTML cleaner missed */
[style*="position:fixed"],
[style*="position: fixed"],
[style*="position:sticky"],
[style*="position: sticky"] {
    display: none !important;
}
/* Hide navigation, footers, sidebars common in docs sites */
nav, .nav, .navbar, .sidebar, .menu,
footer, .footer, .site-footer,
.breadcrumb, .breadcrumbs,
.header-nav, .skip-link,
.edit-page, .page-nav,
[role="navigation"],
[role="banner"],
[aria-label="navigation"],
[aria-label="sidebar"] {
    display: none !important;
}
/* Hide common overlay and widget patterns */
.hamburger, .burger,
[class*="feedbackButton"],
[class*="cornerButton"],
[class*="cookie-banner"],
[class*="cookie-consent"],
[id*="ot-sdk"],
.ot-sdk-show-settings {
    display: none !important;
}
/* Ensure images fit */
img {
    max-width: 100% !important;
    height: auto !important;
}
/* Code blocks */
pre, code {
    font-size: 9pt;
    word-wrap: break-word;
    white-space: pre-wrap;
}
```

## What the Stylesheet Does

### Page Setup

- **Letter size** (8.5" x 11") with 1.5cm margins on all sides.
- Body text set at 11pt with 1.4 line-height for comfortable reading.

### Inline Fixed/Sticky Catch-All

Attribute selectors target any element with `position: fixed` or `position: sticky` in its inline `style` attribute. This is a safety net -- the HTML cleaner catches these too, but elements injected by JavaScript or external stylesheets may have inline styles that weren't in the original HTML.

### Navigation Suppression

Standard HTML elements (`nav`, `footer`) and common class names are hidden. ARIA roles and `aria-label` attributes provide additional coverage for accessible markup patterns.

### Overlay Widget Patterns

Specific attribute selectors target common widget patterns by class and ID substring: feedback buttons, hamburger menus, cookie consent banners, and third-party SDK widgets (OneTrust, etc.).

### Image Handling

Images are constrained to fit within the page width. Without this, wide images or diagrams can overflow the page and be clipped.

### Code Blocks

Code is set at 9pt (smaller than body text) with word-wrapping enabled. This prevents long lines from overflowing the page margin, which is a common issue with code-heavy documentation.

## Customization

To use a custom stylesheet, you have two options:

### Option 1: Modify the Script

Edit the CSS heredoc in the `main()` function (search for `print_css`). Changes apply to all future runs.

### Option 2: Post-Process

You can re-render specific pages with a different stylesheet using WeasyPrint directly:

```zsh
weasyprint -s custom.css https://example.com/page output.pdf
```

## Site-Specific Tips

### Sites with aggressive JavaScript rendering

Some modern documentation sites render content entirely via JavaScript (SPAs). Since `webmanual` fetches raw HTML via curl, JavaScript-rendered content will be missing. Sites that use server-side rendering or static generation work best.

Indicators that a site is JS-rendered:
- The fetched HTML contains mostly `<script>` tags and an empty `<div id="app">`.
- Pages appear blank or show only a loading spinner in the rendered PDF.

### Sites with print stylesheets

Some sites include their own `@media print` CSS. WeasyPrint applies both the site's styles and the custom stylesheet. The custom stylesheet uses `!important` on `display: none` rules to ensure navigation elements are hidden regardless of the site's own print styles.

### Dark-themed sites

WeasyPrint renders pages using the site's default theme. If a site uses a dark background by default, the resulting PDF will have dark pages. There is no automatic theme override. You can add background/color overrides to the print stylesheet if needed:

```css
body {
    background: white !important;
    color: #1a1a1a !important;
}
```
