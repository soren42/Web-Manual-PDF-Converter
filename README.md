# webmanual

[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC%20BY--SA%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)
[![Shell: zsh 5.0+](https://img.shields.io/badge/Shell-zsh%205.0%2B-blue.svg)](https://www.zsh.org/)
[![Platform: macOS | Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-brightgreen.svg)](#platform-support)
[![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-orange.svg)](CHANGELOG.md)

**Generate a multi-page, searchable PDF manual from any website.**

`webmanual` crawls a website starting from a seed URL, intelligently determines which links belong to the same documentation section, renders each page to a print-optimized PDF, and merges everything into a single searchable document -- complete with a cover page and table of contents.

---

## Quick Start

```zsh
# Generate a manual from a documentation site
./webmanual.zsh https://docs.example.com/guide/

# Specify output filename and crawl deeper
./webmanual.zsh -o api-reference.pdf -D 3 https://docs.example.com/api/

# Fast run: skip OCR, limit to 10 pages
./webmanual.zsh --no-ocr -M 10 https://docs.example.com/tutorial/
```

The output is a PDF with:
- A **cover page** displaying the site title, source URL, and generation date
- A **table of contents** listing every included page
- **Each crawled webpage** rendered with print-friendly styling
- **Full-text searchability** via OCR (using OCRmyPDF)

## How It Works

```
Seed URL ──> BFS Crawl ──> Scope Filter ──> Fetch HTML ──> Clean ──> Render PDFs ──> Merge ──> OCR
                │                │                           │                         │
                │                └── Only follows links       │                         └── Cover page
                │                    under the same           └── Strip overlays,           + Table of
                └── Breadth-first    path prefix                  nav chrome,               Contents
                    up to depth N                                 fixed elements
```

1. **Crawl** -- Starting from the seed URL, `webmanual` performs a breadth-first traversal of linked pages, up to a configurable depth and page limit.

2. **Scope** -- The script auto-detects a scope prefix from the seed URL's path. Only links sharing the same scheme, domain, and path prefix are followed. Links to other sections or external sites are ignored.

3. **Clean** -- Each fetched HTML page is analyzed and cleaned before rendering. A Python-based preprocessor parses the page's embedded CSS to identify elements with `position: fixed` or `position: sticky`, then strips those elements along with common UI chrome (hamburger menus, feedback buttons, cookie banners, navigation overlays) from the DOM. This runs automatically with no configuration needed.

4. **Render** -- The cleaned HTML is rendered to PDF using [WeasyPrint](https://weasyprint.org/) with a print-optimized stylesheet. A CSS safety net catches any overlay patterns that survive the HTML cleaning step.

5. **Merge** -- Individual PDFs are merged (via `pdfunite`) with an auto-generated cover page and table of contents prepended.

6. **OCR** -- The final PDF is processed through [OCRmyPDF](https://ocrmypdf.readthedocs.io/) to ensure all text is searchable, even text embedded in images.

## Scope Detection

Scope detection is what makes `webmanual` useful -- it automatically determines which links are "part of the manual" and which lead elsewhere.

Given a seed URL like `https://docs.example.com/guide/getting-started`:

| URL | In Scope? | Why |
|-----|-----------|-----|
| `https://docs.example.com/guide/advanced` | Yes | Same path prefix `/guide/` |
| `https://docs.example.com/guide/api/ref` | Yes | Nested under `/guide/` |
| `https://docs.example.com/blog/post` | No | Different path prefix |
| `https://other.example.com/guide/` | No | Different domain |

Override automatic detection with `-s`/`--scope`:

```zsh
# Widen scope to the entire docs subdomain
./webmanual.zsh -s https://docs.example.com/ https://docs.example.com/guide/intro
```

## Usage

```
webmanual.zsh [OPTIONS] <URL>
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h`, `--help` | Show help message and exit | |
| `-V`, `--version` | Show version information | |
| `-v`, `--verbose` | Increase verbosity (repeatable: `-vvv`) | Normal |
| `-q`, `--quiet` | Suppress all non-error output | |
| `-n`, `--dry-run` | Show what would be done without doing it | |
| `-d`, `--debug` | Enable debug mode (implies `-vvv` + xtrace) | |
| `-o`, `--output FILE` | Output PDF file path | `<domain>-manual.pdf` |
| `-D`, `--depth N` | Maximum crawl depth | `2` |
| `-M`, `--max-pages N` | Maximum pages to include | `50` |
| `-s`, `--scope URL` | Override auto-detected scope prefix | Auto |
| `--no-ocr` | Skip the OCRmyPDF step | OCR enabled |
| `--timeout N` | HTTP timeout in seconds | `30` |

### Examples

```zsh
# Basic usage -- crawl a docs section
./webmanual.zsh https://docs.example.com/guide/

# Deep crawl with high page limit
./webmanual.zsh -D 5 -M 200 -o full-docs.pdf https://docs.example.com/

# Verbose output, custom scope, no OCR
./webmanual.zsh -vv --no-ocr -s https://example.com/docs/ https://example.com/docs/api/intro

# Dry run -- preview what would be crawled
./webmanual.zsh -n https://docs.example.com/guide/

# Quiet mode -- errors only
./webmanual.zsh -q -o manual.pdf https://docs.example.com/guide/
```

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error |
| `2` | Usage/syntax error |
| `66` | Input URL unreachable |
| `69` | Missing dependency |
| `73` | Cannot create output file |
| `78` | Configuration error |

Exit codes follow the BSD `sysexits.h` convention.

## Installation

See [INSTALLATION.md](INSTALLATION.md) for detailed platform-specific instructions.

**Quick version (macOS with Homebrew):**

```zsh
brew install poppler ghostscript ocrmypdf
pip3 install weasyprint
```

Then clone this repository and run `./webmanual.zsh`.

## Requirements

| Dependency | Purpose | Required? |
|------------|---------|-----------|
| **zsh** 5.0+ | Script runtime | Yes |
| **curl** | Fetching web pages | Yes |
| **Python 3** | URL parsing, link extraction | Yes |
| **WeasyPrint** | HTML-to-PDF rendering | Yes |
| **pdfunite** | PDF merging (part of Poppler) | Yes |
| **Ghostscript** | PDF processing | Yes |
| **OCRmyPDF** | Text searchability via OCR | No (skip with `--no-ocr`) |

## Project Structure

```
Web-Manual-PDF-Converter/
├── webmanual.zsh       # Main script
├── README.md           # This file
├── INSTALLATION.md     # Installation and setup guide
└── wiki/               # Project wiki
    ├── Home.md
    ├── Architecture.md
    ├── Scope-Detection.md
    ├── Print-Stylesheet.md
    ├── Troubleshooting.md
    └── FAQ.md
```

## Performance Notes

- Each page requires an HTTP HEAD request (for content-type checking) plus a GET request (for fetching), plus a WeasyPrint render pass. Expect roughly 3--5 seconds per page.
- The OCR step adds additional time proportional to the total page count of the merged PDF. Use `--no-ocr` for faster runs when searchability is not needed.
- Use `-M` to cap the page count for large sites. The default limit of 50 pages is a reasonable starting point.

## Acknowledgments

Built on the [ZSH Script Template](https://github.com/soren42/Shell-Script-Templates) by jason c. kay.

## License

This work is licensed under the [Creative Commons Attribution-ShareAlike 4.0 International License](http://creativecommons.org/licenses/by-sa/4.0/).

Created by jason c. kay <<j@son-kay.com>>
