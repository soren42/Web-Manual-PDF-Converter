# Troubleshooting

## Common Issues

### "No pages were fetched. Check the URL and try again."

**Cause**: The seed URL did not return HTML content, or the HTTP request failed entirely.

**Solutions**:
- Verify the URL is accessible: `curl -I <URL>`
- Check for redirects -- some sites redirect to a different domain or path. Use `-vvv` to see what URLs are being processed.
- Some sites block non-browser user agents. The script uses a browser-like User-Agent string, but particularly aggressive bot protection (Cloudflare, etc.) may still block requests.
- Increase the timeout: `--timeout 60`

### Pages are blank or missing content

**Cause**: The site renders content via JavaScript (a single-page application). `webmanual` fetches raw HTML with curl, so JavaScript is never executed.

**How to confirm**: Run `curl -sS <URL> | grep -c '<script'` -- if the HTML is mostly script tags with an empty body div, the site is JS-rendered.

**Workaround**: There is no built-in workaround for JS-rendered sites. Consider using the site's built-in PDF export if available, or a browser-based capture tool.

### Scope is too broad/narrow

**Symptom**: Too many unrelated pages are included, or expected pages are missing.

**Solutions**:
- Use `-n` (dry run) to preview the scope prefix without crawling.
- Use `-vvv` to see which links are being classified as in-scope vs. out-of-scope (trace-level logging shows each "Out of scope" decision).
- Override the scope with `-s <URL>` to manually set the prefix.
- Adjust `-D` (depth) to control how far from the seed URL the crawler goes.

### "Failed to render: <URL>"

**Cause**: WeasyPrint could not render the page. Common reasons:
- The page returned an error (4xx/5xx) when WeasyPrint fetched it.
- The page has CSS that WeasyPrint cannot parse.
- A resource (image, font, stylesheet) timed out during rendering.

**Solutions**:
- Increase the timeout: `--timeout 60`
- Check if the URL works in a browser.
- Run WeasyPrint manually to see the full error: `weasyprint <URL> test.pdf`

### Overlay artifacts still appear in the PDF

**Cause**: The HTML cleaner and CSS safety net both missed an overlay element. This can happen when:
- The element's positioning is applied entirely from an external stylesheet (not embedded `<style>` blocks) and its class names don't match any known patterns.
- The overlay is injected by JavaScript after page load (the fetched HTML may not contain it, but the site's CSS styles a different element as fixed).

**How to diagnose**: Run with `-vv` and look for the "Stripped N overlay element(s)" message. If N is 0, the cleaner found nothing to remove. Inspect the fetched HTML (the temp directory path is shown in `-d` mode) to identify the offending element's class or ID.

**Solutions**:
- Add the element's class name or ID to the print stylesheet's `display: none` rules. Edit the CSS heredoc in `main()` (search for `print_css`).
- For a permanent fix for a specific site, add the class pattern to the `overlay_class_patterns` list in `write_html_cleaner()`.
- As a quick workaround, you can manually edit the generated PDF in a PDF editor to remove the overlay.

### OCR step fails

**Cause**: OCRmyPDF encountered an error processing the merged PDF.

**Solutions**:
- The script falls back to the non-OCR version automatically when OCR fails. The output PDF is still valid.
- Run OCRmyPDF manually to see detailed errors: `ocrmypdf --skip-text input.pdf output.pdf`
- Ensure Tesseract (the OCR engine) is installed: `tesseract --version`
- Install language data if needed: `brew install tesseract-lang` (macOS) or `apt install tesseract-ocr-<lang>` (Linux).

### "Cannot write output file"

**Cause**: The script cannot write to the output path.

**Solutions**:
- Check that the output directory exists and is writable.
- If using a relative path, ensure the current working directory is writable.
- Specify a different output path with `-o`.

### Large PDFs / slow processing

**Cause**: Crawling many pages or OCRing a large document.

**Solutions**:
- Reduce the page limit: `-M 20`
- Reduce crawl depth: `-D 1`
- Skip OCR for faster output: `--no-ocr`
- Use `-q` (quiet mode) to reduce logging overhead.

## Debug Mode

For detailed diagnostics, use `-d` or `-vvv`:

```zsh
./webmanual.zsh -d -o manual.pdf https://docs.example.com/guide/
```

This shows:
- Every dependency check result
- Temp directory location (inspect intermediate files before cleanup)
- Each URL dequeued, visited, and classified
- Every scope decision (in/out)
- Each render attempt and result
- Full stack traces on errors

To preserve intermediate files for inspection, interrupt the script with Ctrl+C after the crawl or render phase -- the temp directory path is logged at debug level.

## Getting Help

If you encounter an issue not covered here, run the failing command with `-d` and include the full output when reporting the problem.
