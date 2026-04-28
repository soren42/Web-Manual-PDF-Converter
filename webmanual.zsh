#!/usr/bin/env zsh
# -*- mode: zsh; sh-shell: zsh; -*-
# zsh-specific: shellcheck does not apply to zsh scripts
#
# Template: v3.0 (20260124)
# webmanual(1)
#
# Created by jason c. kay <j@son-kay.com>
# Copyright 2022-2026 jason c kay
# Some rights reserved.
#
# This work is licensed under the Creative Commons
# Attribution-ShareAlike 4.0 International License. To
# view a copy of this license, visit
# http://creativecommons.org/licenses/by-sa/4.0/.
#
# Description:
#   Generate a multi-page, searchable PDF manual from a website.
#   Crawls in-scope links starting from a seed URL, renders each
#   page to PDF, merges them, and runs OCR for searchability.
#
# Usage:
#   webmanual [OPTIONS] <URL>
#
# Options:
#   -h, --help          Show this help message and exit
#   -V, --version       Show version information and exit
#   -v, --verbose       Increase verbosity (can be repeated: -vvv)
#   -q, --quiet         Suppress all non-error output
#   -n, --dry-run       Show what would be done without doing it
#   -d, --debug         Enable debug mode (implies -vvv)
#   -o, --output FILE   Output PDF file path
#   -D, --depth N       Maximum crawl depth (default: 2)
#   -M, --max-pages N   Maximum number of pages to include (default: 50)
#   -s, --scope URL     Override auto-detected scope prefix
#   -S, --sitemap URL   Seed the crawl queue from a sitemap.xml URL
#   --no-ocr            Skip the OCRmyPDF step
#   --timeout N         HTTP timeout in seconds (default: 30)
#
# Examples:
#   webmanual https://docs.example.com/guide/
#   webmanual -o manual.pdf -D 3 https://docs.example.com/guide/
#   webmanual -v --no-ocr https://example.com/docs/api/
#
# Compilation:
#   This script is designed to be compatible with zcompile.
#   To compile: zcompile webmanual.zsh
#   This creates webmanual.zsh.zwc (zsh word code) for faster loading.
#
# IMPORTANT: Zsh variable naming caveat:
#   Do NOT use 'path' as a local variable name in functions that invoke
#   subshells (e.g., $(...)). In zsh, 'local path' shadows the global $PATH
#   and causes command lookups to fail in subshells. Use 'cmd_path' or
#   similar instead.

# ==============================================================================
# ZSH STRICT MODE AND SHELL OPTIONS
# ==============================================================================

emulate -L zsh

setopt ERR_EXIT
setopt NO_UNSET
setopt PIPE_FAIL

setopt WARN_CREATE_GLOBAL
setopt NO_CLOBBER
setopt LOCAL_OPTIONS
setopt LOCAL_TRAPS
setopt LOCAL_PATTERNS

setopt EXTENDED_GLOB
setopt NO_NOMATCH
setopt NUMERIC_GLOB_SORT
setopt RC_QUOTES
setopt FUNCTION_ARGZERO
setopt C_BASES
setopt MULTIOS

if [[ ${ZSH_VERSION%%.*} -lt 5 ]]; then
    print -u2 "Error: This script requires zsh 5.0 or later (found: ${ZSH_VERSION})"
    exit 1
fi

# ==============================================================================
# CONSTANTS AND DEFAULTS
# ==============================================================================

typeset -gr SCRIPT_NAME="${${(%):-%x}:t}"
typeset -gr SCRIPT_DIR="${${(%):-%x}:A:h}"
typeset -gr SCRIPT_VERSION="1.1.0"
typeset -gr SCRIPT_AUTHOR="jason c. kay <j@son-kay.com>"

# Exit codes
typeset -gri E_SUCCESS=0
typeset -gri E_GENERAL=1
typeset -gri E_USAGE=2
typeset -gri E_NOINPUT=66
typeset -gri E_UNAVAILABLE=69
typeset -gri E_SOFTWARE=70
typeset -gri E_CANTCREAT=73
typeset -gri E_IOERR=74
typeset -gri E_CONFIG=78

# Verbosity levels
typeset -gri V_QUIET=0
typeset -gri V_NORMAL=1
typeset -gri V_VERBOSE=2
typeset -gri V_DEBUG=3
typeset -gri V_TRACE=4

# Colors
typeset -gA COLORS

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================

typeset -gi VERBOSITY=$V_NORMAL
typeset -g DRY_RUN=false
typeset -ga TEMP_FILES=()
typeset -g TEMP_DIR=""
typeset -gA REQUIRED_BINARIES=()
typeset -gA OPTIONAL_BINARIES=()
typeset -ga POSITIONAL_ARGS=()
typeset -g CONFIG_FILE=""
typeset -g OUTPUT_FILE=""

# Script-specific globals
typeset -gi MAX_DEPTH=2
typeset -gi MAX_PAGES=50
typeset -g SCOPE_PREFIX=""
typeset -g NO_OCR=false
typeset -gi HTTP_TIMEOUT=30
typeset -g SITEMAP_URL=""

# ==============================================================================
# LOGGING AND OUTPUT
# ==============================================================================

init_colors() {
    emulate -L zsh
    if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
        COLORS=(
            reset   $'\033[0m'
            bold    $'\033[1m'
            dim     $'\033[2m'
            red     $'\033[0;31m'
            green   $'\033[0;32m'
            yellow  $'\033[0;33m'
            blue    $'\033[0;34m'
            magenta $'\033[0;35m'
            cyan    $'\033[0;36m'
            white   $'\033[0;37m'
        )
    else
        COLORS=(
            reset '' bold '' dim ''
            red '' green '' yellow '' blue ''
            magenta '' cyan '' white ''
        )
    fi
}

_log() {
    emulate -L zsh
    local level=$1
    shift
    local message="$*"
    local timestamp
    zmodload -F zsh/datetime b:strftime
    strftime -s timestamp '%Y-%m-%d %H:%M:%S'

    # All log output goes to stderr to avoid contaminating stdout
    # (stdout is reserved for data output captured by $(...) calls)
    local color prefix min_verbosity output_fd=2

    case $level in
        trace) color=${COLORS[dim]};                     prefix="TRACE"; min_verbosity=$V_TRACE ;;
        debug) color=${COLORS[cyan]};                    prefix="DEBUG"; min_verbosity=$V_DEBUG ;;
        info)  color=${COLORS[green]};                   prefix="INFO";  min_verbosity=$V_NORMAL ;;
        warn)  color=${COLORS[yellow]};                  prefix="WARN";  min_verbosity=$V_NORMAL ;;
        error) color=${COLORS[red]};                     prefix="ERROR"; min_verbosity=$V_QUIET ;;
        fatal) color="${COLORS[red]}${COLORS[bold]}";    prefix="FATAL"; min_verbosity=$V_QUIET ;;
    esac

    if (( VERBOSITY >= min_verbosity )); then
        print -u $output_fd "${color}[${timestamp}] [${prefix}] ${message}${COLORS[reset]}"
    fi
}

trace() { _log trace "$@" }
debug() { _log debug "$@" }
info()  { _log info "$@" }
warn()  { _log warn "$@" }
error() { _log error "$@" }
fatal() {
    emulate -L zsh
    _log fatal "$1"
    exit ${2:-$E_GENERAL}
}
msg() {
    emulate -L zsh
    if (( VERBOSITY >= V_NORMAL )); then
        print -- "$*"
    fi
}

# ==============================================================================
# ERROR HANDLING AND CLEANUP
# ==============================================================================

print_stack_trace() {
    emulate -L zsh
    error "Stack trace:"
    local i
    for (( i = 1; i <= ${#funcstack[@]}; i++ )); do
        error "  at ${funcstack[$i]}() in ${funcsourcetrace[$i]}"
    done
}

TRAPZERR() {
    emulate -L zsh
    local exit_code=$?
    [[ -o ERR_EXIT ]] || return 0
    error "Command failed with exit code ${exit_code}"
    error "  Function: ${funcstack[2]:-main}"
    error "  Source: ${funcsourcetrace[2]:-unknown}"
    if (( VERBOSITY >= V_DEBUG )); then
        print_stack_trace
    fi
}

TRAPEXIT() {
    emulate -L zsh
    local exit_code=$?
    local temp_file
    for temp_file in "${TEMP_FILES[@]}"; do
        [[ -f "$temp_file" ]] && rm -f "$temp_file" 2>/dev/null
    done
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        debug "Removing temp directory: ${TEMP_DIR}"
        rm -rf "$TEMP_DIR" 2>/dev/null
    fi
    debug "Cleanup complete, exiting with code ${exit_code}"
    return $exit_code
}

TRAPINT()  { error "Caught signal: INT";  return $(( 128 + 2 )) }
TRAPTERM() { error "Caught signal: TERM"; return $(( 128 + 15 )) }
TRAPHUP()  { error "Caught signal: HUP";  return $(( 128 + 1 )) }

setup_traps() {
    emulate -L zsh
    debug "Trap handlers configured"
}

# ==============================================================================
# DEPENDENCY VALIDATION
# ==============================================================================

command_exists() {
    emulate -L zsh
    (( $+commands[$1] ))
}

get_command() {
    emulate -L zsh
    local cmd
    for cmd in "$@"; do
        if (( $+commands[$cmd] )); then
            print -- "${commands[$cmd]}"
            return 0
        fi
    done
    return 1
}

require_binary() {
    emulate -L zsh
    local name=$1
    shift
    local -a alternatives=("$name" "$@")
    local cmd_path
    if cmd_path=$(get_command "${alternatives[@]}"); then
        REQUIRED_BINARIES[$name]=$cmd_path
        debug "Found required binary: ${name} -> ${cmd_path}"
        return 0
    fi
    error "Required binary not found: ${name}"
    error "Tried: ${(j:, :)alternatives}"
    exit $E_UNAVAILABLE
}

optional_binary() {
    emulate -L zsh
    local name=$1
    shift
    local -a alternatives=("$name" "$@")
    local cmd_path
    if cmd_path=$(get_command "${alternatives[@]}"); then
        OPTIONAL_BINARIES[$name]=$cmd_path
        debug "Found optional binary: ${name} -> ${cmd_path}"
        return 0
    fi
    OPTIONAL_BINARIES[$name]=""
    debug "Optional binary not found: ${name}"
    return 1
}

validate_dependencies() {
    emulate -L zsh
    debug "Validating dependencies..."

    require_binary curl
    require_binary python3
    require_binary weasyprint
    require_binary pdfunite
    require_binary gs ghostscript

    if [[ $NO_OCR == false ]]; then
        require_binary ocrmypdf
    fi

    debug "All required dependencies satisfied"
}

# ==============================================================================
# TEMP FILE MANAGEMENT
# ==============================================================================

create_temp_file() {
    emulate -L zsh
    local suffix=${1:-}
    local temp_file

    # macOS mktemp requires X's at the end of the template, so create
    # without suffix then rename if a suffix was requested
    temp_file=$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.XXXXXX") || {
        fatal "Failed to create temporary file" $E_CANTCREAT
    }

    if [[ -n "$suffix" ]]; then
        local renamed="${temp_file}${suffix}"
        mv "$temp_file" "$renamed"
        temp_file="$renamed"
    fi

    TEMP_FILES+=("$temp_file")
    debug "Created temp file: ${temp_file}"
    print -- "$temp_file"
}

create_temp_dir() {
    emulate -L zsh
    if [[ -n "${TEMP_DIR:-}" ]]; then
        print -- "$TEMP_DIR"
        return 0
    fi
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_NAME}.XXXXXX") || {
        fatal "Failed to create temporary directory" $E_CANTCREAT
    }
    debug "Created temp directory: ${TEMP_DIR}"
    print -- "$TEMP_DIR"
}

# ==============================================================================
# USAGE AND HELP
# ==============================================================================

usage() {
    emulate -L zsh
    print -u2 "Usage: ${SCRIPT_NAME} [OPTIONS] <URL>"
    print -u2 "Try '${SCRIPT_NAME} --help' for more information."
}

show_help() {
    emulate -L zsh
    print -r -- "\
${SCRIPT_NAME} - Generate a multi-page, searchable PDF manual from a website

Usage:
    ${SCRIPT_NAME} [OPTIONS] <URL>

Options:
    -h, --help              Show this help message and exit
    -V, --version           Show version information and exit
    -v, --verbose           Increase verbosity level (can be repeated)
    -q, --quiet             Suppress all non-error output
    -n, --dry-run           Show what would be done without doing it
    -d, --debug             Enable debug mode (implies maximum verbosity)
    -o, --output FILE       Write output to FILE (default: <domain>-manual.pdf)
    -D, --depth N           Maximum crawl depth (default: 2)
    -M, --max-pages N       Maximum number of pages to include (default: 50)
    -s, --scope URL         Override the auto-detected scope prefix
    -S, --sitemap URL       Seed crawl queue from a sitemap.xml URL.
                            Useful for sites with JS-rendered navigation
                            where link extraction returns nothing.
                            Sitemap-index files are followed recursively.
                            URLs are still filtered by scope.
    --no-ocr                Skip the OCRmyPDF searchability step
    --timeout N             HTTP timeout in seconds (default: 30)

Arguments:
    URL                     The seed URL to start crawling from

How scope detection works:
    The script auto-detects the \"scope\" of the manual based on the seed URL.
    Only links sharing the same scheme, domain, and path prefix are followed.

    For example, given https://docs.example.com/guide/getting-started:
      - In scope:  https://docs.example.com/guide/advanced
      - In scope:  https://docs.example.com/guide/api/reference
      - Out of scope: https://docs.example.com/blog/post
      - Out of scope: https://other.example.com/guide/

    Use -s/--scope to override this. For example:
      ${SCRIPT_NAME} -s https://docs.example.com/ https://docs.example.com/guide/

Examples:
    ${SCRIPT_NAME} https://docs.example.com/guide/
        Crawl the guide section and produce docs.example.com-manual.pdf

    ${SCRIPT_NAME} -o manual.pdf -D 3 -M 100 https://docs.example.com/guide/
        Crawl 3 levels deep, up to 100 pages, output to manual.pdf

    ${SCRIPT_NAME} -v --no-ocr https://example.com/docs/api/
        Verbose mode, skip OCR step

    ${SCRIPT_NAME} -S https://example.com/sitemap.xml https://example.com/docs/
        Seed crawl queue from a sitemap (useful for JS-rendered sites
        that don't expose links in their HTML)

Exit Codes:
    0   Success
    1   General error
    2   Usage/syntax error
    66  Input URL unreachable
    69  Missing dependency
    73  Cannot create output file
    78  Configuration error

Report bugs to: ${SCRIPT_AUTHOR}"
}

show_version() {
    emulate -L zsh
    print "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

parse_arguments() {
    emulate -L zsh
    zmodload zsh/zutil

    local -a opt_help opt_version opt_verbose opt_quiet opt_dry_run opt_debug
    local -a opt_output opt_depth opt_max_pages opt_scope opt_sitemap opt_no_ocr opt_timeout

    zparseopts -D -E -F -K -- \
        h=opt_help      -help=opt_help \
        V=opt_version   -version=opt_version \
        v+=opt_verbose  -verbose+=opt_verbose \
        q=opt_quiet     -quiet=opt_quiet \
        n=opt_dry_run   -dry-run=opt_dry_run \
        d=opt_debug     -debug=opt_debug \
        o:=opt_output   -output:=opt_output \
        D:=opt_depth    -depth:=opt_depth \
        M:=opt_max_pages -max-pages:=opt_max_pages \
        s:=opt_scope    -scope:=opt_scope \
        S:=opt_sitemap  -sitemap:=opt_sitemap \
        -no-ocr=opt_no_ocr \
        -timeout:=opt_timeout \
        || {
            usage
            exit $E_USAGE
        }

    if (( ${#opt_help} )); then
        show_help
        exit $E_SUCCESS
    fi

    if (( ${#opt_version} )); then
        show_version
        exit $E_SUCCESS
    fi

    if (( ${#opt_verbose} )); then
        VERBOSITY=$(( V_NORMAL + ${#opt_verbose} ))
        (( VERBOSITY > V_TRACE )) && VERBOSITY=$V_TRACE
    fi

    (( ${#opt_quiet} ))   && VERBOSITY=$V_QUIET
    (( ${#opt_dry_run} )) && DRY_RUN=true

    if (( ${#opt_debug} )); then
        VERBOSITY=$V_TRACE
        setopt XTRACE
    fi

    (( ${#opt_output} ))    && OUTPUT_FILE=${opt_output[-1]}
    (( ${#opt_depth} ))     && MAX_DEPTH=${opt_depth[-1]}
    (( ${#opt_max_pages} )) && MAX_PAGES=${opt_max_pages[-1]}
    (( ${#opt_scope} ))     && SCOPE_PREFIX=${opt_scope[-1]}
    (( ${#opt_sitemap} ))   && SITEMAP_URL=${opt_sitemap[-1]}
    (( ${#opt_no_ocr} ))    && NO_OCR=true
    (( ${#opt_timeout} ))   && HTTP_TIMEOUT=${opt_timeout[-1]}

    [[ ${1:-} == '--' ]] && shift
    POSITIONAL_ARGS=("$@")

    debug "Verbosity: ${VERBOSITY}, Dry run: ${DRY_RUN}"
    debug "Max depth: ${MAX_DEPTH}, Max pages: ${MAX_PAGES}"
    debug "Positional arguments: ${(j:, :)POSITIONAL_ARGS:-none}"
}

validate_arguments() {
    emulate -L zsh

    if (( ${#POSITIONAL_ARGS} < 1 )); then
        error "Missing required argument: URL"
        usage
        exit $E_USAGE
    fi

    if (( ${#POSITIONAL_ARGS} > 1 )); then
        error "Too many arguments; expected a single URL"
        usage
        exit $E_USAGE
    fi

    local url="${POSITIONAL_ARGS[1]}"
    if [[ "$url" != http://* ]] && [[ "$url" != https://* ]]; then
        error "URL must start with http:// or https://"
        exit $E_USAGE
    fi

    debug "Arguments validated successfully"
}

# ==============================================================================
# DRY RUN SUPPORT
# ==============================================================================

run() {
    emulate -L zsh
    if [[ $DRY_RUN == true ]]; then
        info "[DRY-RUN] Would execute: $*"
        return 0
    fi
    debug "Executing: $*"
    "$@"
}

# ==============================================================================
# URL UTILITIES
# ==============================================================================

# Extract scheme, host, and path from a URL using Python (reliable parsing)
# Arguments: $1 - URL
# Outputs: scheme\nhost\npath (one per line)
parse_url() {
    emulate -L zsh
    python3 -c "
from urllib.parse import urlparse
u = urlparse('$1')
print(u.scheme)
print(u.netloc)
print(u.path)
"
}

# Normalize a URL: resolve relative references, strip fragments, normalize path
# Arguments: $1 - base URL, $2 - href to resolve
# Outputs: normalized absolute URL (no fragment)
normalize_url() {
    emulate -L zsh
    python3 -c "
from urllib.parse import urljoin, urldefrag, urlparse
base = '$1'
href = '$2'
joined = urljoin(base, href)
defragged, _ = urldefrag(joined)
# Strip trailing index pages for consistency
import re
defragged = re.sub(r'/index\.html?$', '/', defragged)
print(defragged)
"
}

# Determine the scope prefix from a seed URL
# The scope is scheme://host/path-up-to-last-slash/
# Arguments: $1 - seed URL
# Outputs: scope prefix URL
compute_scope() {
    emulate -L zsh
    python3 -c "
from urllib.parse import urlparse
import re
u = urlparse('$1')
# Use the directory portion of the path as scope
p = u.path
# Strip trailing index pages
p = re.sub(r'/index\.html?$', '/', p)
# If path doesn't end with /, take the directory
if not p.endswith('/'):
    p = p.rsplit('/', 1)[0] + '/'
scope = f'{u.scheme}://{u.netloc}{p}'
print(scope)
"
}

# Check if a URL is within scope
# Arguments: $1 - URL to check, $2 - scope prefix
# Returns: 0 if in scope, 1 if out of scope
url_in_scope() {
    emulate -L zsh
    local test_url="$1"
    local scope="$2"
    [[ "$test_url" == ${scope}* ]]
}

# ==============================================================================
# CRAWLING AND LINK EXTRACTION
# ==============================================================================

# Extract links from an HTML document, resolving them against a base URL.
# Filters to only http/https links and deduplicates.
# Arguments: $1 - HTML file path, $2 - base URL
# Outputs: one absolute URL per line
extract_links() {
    emulate -L zsh
    local html_file="$1"
    local base_url="$2"

    python3 -c "
import sys, re
from html.parser import HTMLParser
from urllib.parse import urljoin, urldefrag, urlparse

class LinkExtractor(HTMLParser):
    def __init__(self, base):
        super().__init__()
        self.base = base
        self.links = set()

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            for name, value in attrs:
                if name == 'href' and value:
                    try:
                        absolute = urljoin(self.base, value)
                        defragged, _ = urldefrag(absolute)
                        # Normalize trailing index pages
                        defragged = re.sub(r'/index\.html?$', '/', defragged)
                        parsed = urlparse(defragged)
                        if parsed.scheme in ('http', 'https'):
                            self.links.add(defragged)
                    except Exception:
                        pass

with open('$html_file', 'r', errors='replace') as f:
    html = f.read()

extractor = LinkExtractor('$base_url')
extractor.feed(html)

for link in sorted(extractor.links):
    print(link)
" 2>/dev/null || true
}

# Fetch a URL to a file using curl
# Arguments: $1 - URL, $2 - output file path
# Returns: curl exit code
fetch_url() {
    emulate -L zsh
    local url="$1"
    local out_file="$2"

    curl -sS -L \
        --max-time "$HTTP_TIMEOUT" \
        --retry 2 \
        --retry-delay 1 \
        -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) WebManual/${SCRIPT_VERSION}" \
        -o "$out_file" \
        "$url" 2>/dev/null
}

# Check if a URL returns HTML content
# Arguments: $1 - URL
# Returns: 0 if HTML, 1 otherwise
is_html_content() {
    emulate -L zsh
    local url="$1"
    local content_type

    content_type=$(curl -sS -L -I \
        --max-time "$HTTP_TIMEOUT" \
        -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) WebManual/${SCRIPT_VERSION}" \
        "$url" 2>/dev/null | grep -i '^content-type:' | tail -1) || return 1

    [[ "$content_type" == *text/html* ]]
}

# Extract the page title from an HTML file
# Arguments: $1 - HTML file path
# Outputs: page title (or empty string)
extract_title() {
    emulate -L zsh
    local html_file="$1"

    python3 -c "
import re, sys
with open('$html_file', 'r', errors='replace') as f:
    html = f.read()
m = re.search(r'<title[^>]*>(.*?)</title>', html, re.IGNORECASE | re.DOTALL)
if m:
    title = re.sub(r'\s+', ' ', m.group(1)).strip()
    print(title)
" 2>/dev/null || true
}

# ==============================================================================
# HTML CLEANING FOR PRINT
# ==============================================================================

# Write the HTML cleaner Python script to the work directory.
# Called once; the script is then reused for every page.
# Arguments: $1 - output script path
# Outputs: None (writes file)
write_html_cleaner() {
    emulate -L zsh
    local script_path="$1"

    cat >| "$script_path" << 'PYEOF'
#!/usr/bin/env python3
"""Strip overlay/chrome elements from HTML for print rendering."""
import sys, re, os
from html.parser import HTMLParser

input_path  = sys.argv[1]
output_path = sys.argv[2]
base_url    = sys.argv[3]

with open(input_path, "r", errors="replace") as f:
    html = f.read()

# ── Phase 1: Extract selectors with position:fixed or position:sticky ──
# Parse all <style> blocks for rules containing these properties.
# We extract the selector portion of each matching rule.

fixed_selectors = set()
style_blocks = re.findall(r"<style[^>]*>(.*?)</style>", html, re.DOTALL | re.IGNORECASE)
for block in style_blocks:
    # Remove CSS comments
    block = re.sub(r"/\*.*?\*/", "", block, flags=re.DOTALL)
    # Find rules with position:fixed or position:sticky
    # Pattern: selector(s) { ... position: fixed|sticky ... }
    for m in re.finditer(
        r"([^{}]+?)\{([^{}]*?position\s*:\s*(?:fixed|sticky)[^{}]*?)\}",
        block, re.DOTALL | re.IGNORECASE
    ):
        raw_selectors = m.group(1).strip()
        for sel in raw_selectors.split(","):
            sel = sel.strip()
            if sel:
                fixed_selectors.add(sel)

# ── Phase 2: Convert CSS selectors to class/id patterns ──
# We extract class names and IDs from the selectors to match against HTML.

fixed_classes = set()
fixed_ids = set()
for sel in fixed_selectors:
    for cls in re.findall(r"\.([a-zA-Z0-9_-]+)", sel):
        fixed_classes.add(cls)
    for eid in re.findall(r"#([a-zA-Z0-9_-]+)", sel):
        fixed_ids.add(eid)

# ── Phase 3: Define known overlay patterns (site-agnostic) ──
# These catch common UI chrome that may not use position:fixed in
# embedded styles (e.g., applied via external CSS or JS).

overlay_class_patterns = [
    # Navigation
    r"(?:^|[-_])nav(?:bar|container|brand|btn)(?:[-_]|$)",
    r"(?:^|[-_])sidebar(?:[-_]|$)",
    r"(?:^|[-_])side[-_]?bar(?:[-_]|$)",
    # Menus and hamburgers
    r"(?:^|[-_])hamburger(?:[-_]|$)",
    r"(?:^|[-_])burger(?:[-_]|$)",
    r"(?:^|[-_])menu[-_]?(?:toggle|btn|button)(?:[-_]|$)",
    # Feedback and widgets
    r"(?:^|[-_])feedback(?:[-_]?button)?(?:[-_]|$)",
    r"(?:^|[-_])ot[-_]sdk(?:[-_]|$)",
    # Breadcrumbs, TOC, footers
    r"(?:^|[-_])breadcrumb",
    r"(?:^|[-_])skip[-_]?(?:link|nav|to)",
    r"(?:^|[-_])cookie[-_]?(?:banner|consent|notice)",
    r"(?:^|[-_])(?:corner[-_]?button)",
    # Generic overlays
    r"(?:^|[-_])overlay(?:[-_]|$)",
    r"(?:^|[-_])modal(?:[-_]|$)",
    r"(?:^|[-_])toast(?:[-_]|$)",
    r"(?:^|[-_])snackbar(?:[-_]|$)",
    r"(?:^|[-_])popup(?:[-_]|$)",
    r"(?:^|[-_])tooltip(?:[-_]|$)",
    r"(?:^|[-_])banner(?:[-_]|$)",
]
overlay_class_re = [re.compile(p, re.IGNORECASE) for p in overlay_class_patterns]

overlay_id_patterns = [
    r"^navBtn$", r"^searchBtn$", r"^ot-sdk-btn$",
    r"^cookie", r"^feedback",
]
overlay_id_re = [re.compile(p, re.IGNORECASE) for p in overlay_id_patterns]

overlay_roles = {"navigation", "banner"}

# ── Phase 4: Parse and rebuild HTML, stripping overlay elements ──

class OverlayStripper(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.output = []
        self.skip_depth = 0  # > 0 means we're inside an element being stripped
        self.stripped_count = 0

    def _should_strip(self, tag, attrs):
        attr_dict = dict(attrs)

        # Check inline style for position:fixed/sticky
        style = attr_dict.get("style", "")
        if re.search(r"position\s*:\s*(?:fixed|sticky)", style, re.IGNORECASE):
            return True

        # Check role
        role = attr_dict.get("role", "").lower()
        if role in overlay_roles:
            return True

        # Check aria-label for common overlay hints
        aria = attr_dict.get("aria-label", "").lower()
        if any(kw in aria for kw in ("navigation", "menu", "sidebar", "feedback")):
            return True

        # Check id
        elem_id = attr_dict.get("id", "")
        if elem_id:
            if elem_id in fixed_ids:
                return True
            for pat in overlay_id_re:
                if pat.search(elem_id):
                    return True

        # Check classes
        classes = attr_dict.get("class", "").split()
        for cls in classes:
            if cls in fixed_classes:
                return True
            for pat in overlay_class_re:
                if pat.search(cls):
                    return True

        return False

    def handle_starttag(self, tag, attrs):
        if self.skip_depth > 0:
            self.skip_depth += 1
            return

        if self._should_strip(tag, attrs):
            self.skip_depth = 1
            self.stripped_count += 1
            return

        attr_str = ""
        for name, value in attrs:
            if value is None:
                attr_str += f" {name}"
            else:
                value_escaped = value.replace("&", "&amp;").replace('"', "&quot;")
                attr_str += f' {name}="{value_escaped}"'
        self.output.append(f"<{tag}{attr_str}>")

    def handle_endtag(self, tag):
        if self.skip_depth > 0:
            self.skip_depth -= 1
            return
        self.output.append(f"</{tag}>")

    def handle_data(self, data):
        if self.skip_depth == 0:
            self.output.append(data)

    def handle_entityref(self, name):
        if self.skip_depth == 0:
            self.output.append(f"&{name};")

    def handle_charref(self, name):
        if self.skip_depth == 0:
            self.output.append(f"&#{name};")

    def handle_comment(self, data):
        if self.skip_depth == 0:
            self.output.append(f"<!--{data}-->")

    def handle_decl(self, decl):
        self.output.append(f"<!{decl}>")

    def handle_pi(self, data):
        if self.skip_depth == 0:
            self.output.append(f"<?{data}>")

    def unknown_decl(self, data):
        if self.skip_depth == 0:
            self.output.append(f"<![{data}]>")

# ── Phase 5: Inject a <base> tag so relative resources resolve correctly ──
# When rendering a local file, WeasyPrint needs to know the original URL
# for loading images, stylesheets, and fonts.

stripper = OverlayStripper()
stripper.feed(html)
cleaned = "".join(stripper.output)

# Inject <base href="..."> if not already present
if not re.search(r"<base\s", cleaned, re.IGNORECASE):
    cleaned = re.sub(
        r"(<head[^>]*>)",
        rf'\1<base href="{base_url}">',
        cleaned,
        count=1,
        flags=re.IGNORECASE,
    )

with open(output_path, "w") as f:
    f.write(cleaned)

if stripper.stripped_count > 0:
    src = os.path.basename(input_path)
    print(f"  Stripped {stripper.stripped_count} overlay element(s) from {src}", file=sys.stderr)
PYEOF
}

# Run the HTML cleaner on a single file.
# Arguments: $1 - input HTML path, $2 - output cleaned HTML path,
#            $3 - base URL, $4 - cleaner script path
# Returns: 0 on success
clean_html_for_print() {
    emulate -L zsh
    python3 "$4" "$1" "$2" "$3"
}

# ==============================================================================
# SITEMAP PARSING
# ==============================================================================

# Parse a sitemap XML file.
# Outputs one entry per line, prefixed with type:
#   loc<TAB>https://...   for content URLs (from <urlset>)
#   sub<TAB>https://...   for sub-sitemap URLs (from <sitemapindex>)
# Arguments: $1 - XML file path
parse_sitemap_xml() {
    emulate -L zsh
    local xml_file="$1"

    python3 -c "
import sys
import xml.etree.ElementTree as ET

def strip_ns(tag):
    return tag.split('}', 1)[1] if '}' in tag else tag

try:
    tree = ET.parse('$xml_file')
    root = tree.getroot()
except ET.ParseError as e:
    sys.stderr.write(f'sitemap parse error: {e}\n')
    sys.exit(1)
except Exception as e:
    sys.stderr.write(f'sitemap read error: {e}\n')
    sys.exit(1)

root_tag = strip_ns(root.tag)

if root_tag == 'sitemapindex':
    for sm in root:
        if strip_ns(sm.tag) != 'sitemap':
            continue
        for child in sm:
            if strip_ns(child.tag) == 'loc' and child.text:
                print(f'sub\t{child.text.strip()}')
elif root_tag == 'urlset':
    for url in root:
        if strip_ns(url.tag) != 'url':
            continue
        for child in url:
            if strip_ns(child.tag) == 'loc' and child.text:
                print(f'loc\t{child.text.strip()}')
else:
    sys.stderr.write(f'unexpected sitemap root element: {root_tag}\n')
    sys.exit(1)
" 2>/dev/null
}

# Recursively collect content URLs from a sitemap.
# Follows <sitemapindex> entries up to a recursion depth limit.
# Arguments: $1 - sitemap URL, $2 - work dir, $3 - recursion depth (default 0)
# Outputs: one URL per line on stdout
collect_sitemap_urls() {
    emulate -L zsh
    local sitemap_url="$1"
    local work_dir="$2"
    local -i rec_depth=${3:-0}

    if (( rec_depth > 5 )); then
        warn "Sitemap recursion depth exceeded; skipping ${sitemap_url}"
        return 0
    fi

    local sitemap_file="${work_dir}/sitemap_${rec_depth}_${RANDOM}.xml"
    debug "Fetching sitemap: ${sitemap_url}"
    if ! fetch_url "$sitemap_url" "$sitemap_file"; then
        warn "Failed to fetch sitemap: ${sitemap_url}"
        return 1
    fi

    local entry_type="" entry_url=""
    while IFS=$'\t' read -r entry_type entry_url; do
        case "$entry_type" in
            loc)
                print -- "$entry_url"
                ;;
            sub)
                collect_sitemap_urls "$entry_url" "$work_dir" $(( rec_depth + 1 ))
                ;;
        esac
    done < <(parse_sitemap_xml "$sitemap_file")
}

# ==============================================================================
# PDF GENERATION
# ==============================================================================

# Render a single page to PDF using weasyprint from cleaned local HTML
# Arguments: $1 - local HTML path, $2 - output PDF path, $3 - CSS file path
#            $4 - base URL (for resource resolution), $5 - work dir,
#            $6 - cleaner script path
# Returns: 0 on success, non-zero on failure
render_page_to_pdf() {
    emulate -L zsh
    local html_file="$1"
    local pdf_out="$2"
    local css_file="$3"
    local base_url="$4"
    local render_work_dir="$5"
    local cleaner_script="$6"

    # Clean the HTML: strip overlays, fixed elements, nav chrome
    local cleaned_html="${render_work_dir}/cleaned_$(basename "$html_file")"

    clean_html_for_print "$html_file" "$cleaned_html" "$base_url" "$cleaner_script" || true

    weasyprint \
        -s "$css_file" \
        -e utf-8 \
        --timeout "$HTTP_TIMEOUT" \
        -u "$base_url" \
        "$cleaned_html" "$pdf_out" 2>/dev/null

    return $?
}

# Create a cover/title page PDF
# Arguments: $1 - title, $2 - seed URL, $3 - date, $4 - output PDF path, $5 - work dir
generate_cover_page() {
    emulate -L zsh
    local title="$1"
    local seed_url="$2"
    local gen_date="$3"
    local pdf_out="$4"
    local work_dir="$5"

    local html_file="${work_dir}/cover.html"

    cat >| "$html_file" <<HTMLEOF
<!DOCTYPE html>
<html>
<head><meta charset="utf-8">
<style>
@page { size: Letter; margin: 0; }
body {
    font-family: -apple-system, Helvetica Neue, Helvetica, Arial, sans-serif;
    display: flex; align-items: center; justify-content: center;
    height: 100vh; margin: 0; background: #f8f9fa;
}
.cover {
    text-align: center; padding: 3em;
}
h1 { font-size: 2.5em; color: #1a1a2e; margin-bottom: 0.3em; }
.url { font-size: 1em; color: #555; font-family: monospace; margin: 1em 0; }
.date { font-size: 0.9em; color: #888; margin-top: 2em; }
.gen { font-size: 0.8em; color: #aaa; margin-top: 1em; }
</style>
</head>
<body>
<div class="cover">
    <h1>${title}</h1>
    <div class="url">${seed_url}</div>
    <div class="date">Generated: ${gen_date}</div>
    <div class="gen">Created with webmanual</div>
</div>
</body>
</html>
HTMLEOF

    weasyprint "$html_file" "$pdf_out" 2>/dev/null
}

# Create a table-of-contents page PDF
# Arguments: $1 - toc entries file (title\turl per line), $2 - output PDF path, $3 - work dir
generate_toc_page() {
    emulate -L zsh
    local toc_file="$1"
    local pdf_out="$2"
    local work_dir="$3"

    local html_file="${work_dir}/toc.html"

    # Build TOC HTML from entries
    local toc_items=""
    local -i line_num=0
    local entry_title="" entry_url=""
    while IFS=$'\t' read -r entry_title entry_url; do
        (( line_num++ ))
        [[ -z "$entry_title" ]] && entry_title="$entry_url"
        toc_items+="<li><span class=\"num\">${line_num}.</span> ${entry_title}<br><span class=\"url\">${entry_url}</span></li>"
    done < "$toc_file"

    cat >| "$html_file" <<HTMLEOF
<!DOCTYPE html>
<html>
<head><meta charset="utf-8">
<style>
@page { size: Letter; margin: 1.5cm; }
body {
    font-family: -apple-system, Helvetica Neue, Helvetica, Arial, sans-serif;
    font-size: 11pt; line-height: 1.6; color: #1a1a2e;
}
h2 { border-bottom: 2px solid #1a1a2e; padding-bottom: 0.3em; }
ol { list-style: none; padding-left: 0; }
li { margin-bottom: 0.8em; }
.num { font-weight: bold; color: #333; }
.url { font-size: 0.8em; color: #666; font-family: monospace; word-break: break-all; }
</style>
</head>
<body>
<h2>Table of Contents</h2>
<ol>${toc_items}</ol>
</body>
</html>
HTMLEOF

    weasyprint "$html_file" "$pdf_out" 2>/dev/null
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

main() {
    emulate -L zsh
    debug "Starting main execution"

    local seed_url="${POSITIONAL_ARGS[1]}"
    local work_dir
    work_dir=$(create_temp_dir)

    # Determine scope
    if [[ -z "$SCOPE_PREFIX" ]]; then
        SCOPE_PREFIX=$(compute_scope "$seed_url")
    fi
    info "Seed URL: ${seed_url}"
    info "Scope prefix: ${SCOPE_PREFIX}"

    # Determine output file name
    if [[ -z "$OUTPUT_FILE" ]]; then
        local domain
        domain=$(python3 -c "from urllib.parse import urlparse; print(urlparse('${seed_url}').netloc)")
        OUTPUT_FILE="${domain}-manual.pdf"
    fi
    info "Output file: ${OUTPUT_FILE}"

    if [[ $DRY_RUN == true ]]; then
        info "[DRY-RUN] Would crawl ${seed_url} (depth=${MAX_DEPTH}, max=${MAX_PAGES})"
        info "[DRY-RUN] Would generate ${OUTPUT_FILE}"
        return $E_SUCCESS
    fi

    # ---- BFS Crawl ----
    # visited: associative array of URL -> 1
    # queue: file with URL\tdepth per line
    typeset -A visited
    local queue_file="${work_dir}/queue"
    local page_list="${work_dir}/page_list"  # ordered list of URLs to include

    print "${seed_url}\t0" >| "$queue_file"
    : >| "$page_list"

    local -i page_count=0
    local current_line="" current_url="" current_depth=""
    local page_file="" title="" link=""
    local -a links=()
    local -i sitemap_added=0
    local sm_url=""

    # If a sitemap was provided, expand it into the crawl queue.
    # Sitemap URLs are enqueued at depth 0 so their links are also explored
    # (subject to MAX_DEPTH). All entries are filtered by scope.
    if [[ -n "$SITEMAP_URL" ]]; then
        info "Loading sitemap: ${SITEMAP_URL}"
        while IFS= read -r sm_url; do
            [[ -z "$sm_url" ]] && continue
            if url_in_scope "$sm_url" "$SCOPE_PREFIX"; then
                print "${sm_url}\t0" >> "$queue_file"
                (( sitemap_added++ ))
            else
                trace "Sitemap URL out of scope: ${sm_url}"
            fi
        done < <(collect_sitemap_urls "$SITEMAP_URL" "$work_dir" 0)
        info "Sitemap added ${sitemap_added} in-scope URL(s) to queue"
    fi

    info "Crawling..."

    while [[ -s "$queue_file" ]]; do
        # Read first line from queue and rotate
        IFS= read -r current_line < "$queue_file"
        sed '1d' "$queue_file" >| "${queue_file}.tmp"
        mv "${queue_file}.tmp" "$queue_file"

        current_url="${current_line%%$'\t'*}"
        current_depth="${current_line##*$'\t'}"

        # Skip if already visited
        [[ -n "${visited[$current_url]:-}" ]] && continue
        visited[$current_url]=1

        # Respect max pages (check before any network calls)
        if (( page_count >= MAX_PAGES )); then
            warn "Reached max page limit (${MAX_PAGES}), stopping crawl"
            break
        fi

        # Skip non-HTML content
        if ! is_html_content "$current_url"; then
            debug "Skipping non-HTML: ${current_url}"
            continue
        fi

        # Fetch the page
        page_file="${work_dir}/page_${page_count}.html"
        if fetch_url "$current_url" "$page_file"; then
            (( page_count++ ))
            print "$current_url" >> "$page_list"

            title=$(extract_title "$page_file")
            if (( VERBOSITY >= V_VERBOSE )); then
                info "[${page_count}/${MAX_PAGES}] (depth ${current_depth}) ${title:-${current_url}}"
            else
                info "[${page_count}/${MAX_PAGES}] ${title:-${current_url}}"
            fi

            # Extract and enqueue links if we haven't hit max depth
            if (( current_depth < MAX_DEPTH )); then
                links=("${(@f)$(extract_links "$page_file" "$current_url")}")
                for link in "${links[@]}"; do
                    [[ -z "$link" ]] && continue
                    [[ -n "${visited[$link]:-}" ]] && continue
                    if url_in_scope "$link" "$SCOPE_PREFIX"; then
                        print "${link}\t$(( current_depth + 1 ))" >> "$queue_file"
                    else
                        trace "Out of scope: ${link}"
                    fi
                done
            fi
        else
            warn "Failed to fetch: ${current_url}"
        fi
    done

    if (( page_count == 0 )); then
        fatal "No pages were fetched. Check the URL and try again." $E_NOINPUT
    fi

    info "Crawled ${page_count} page(s). Rendering PDFs..."

    # ---- Create HTML cleaner script (once) ----
    local cleaner_script="${work_dir}/html_cleaner.py"
    write_html_cleaner "$cleaner_script"

    # ---- Create print stylesheet (once) ----
    local print_css="${work_dir}/print.css"
    cat >| "$print_css" <<'CSSEOF'
@page {
    size: Letter;
    margin: 1.5cm;
}
body {
    font-size: 11pt;
    line-height: 1.4;
    max-width: 100%;
}
/* ── CSS safety net: catch any fixed/sticky elements the HTML cleaner missed ── */
/* Force any surviving fixed/sticky elements out of the viewport */
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
CSSEOF

    # ---- Render each page to PDF ----
    local -a pdf_parts=()
    local toc_entries="${work_dir}/toc_entries"
    : >| "$toc_entries"

    local -i render_num=0
    local page_url="" page_pdf="" page_html="" page_title=""
    while IFS= read -r page_url; do
        page_pdf="${work_dir}/render_${render_num}.pdf"
        page_html="${work_dir}/page_${render_num}.html"

        page_title=$(extract_title "$page_html")

        info "Rendering [$(( render_num + 1 ))/${page_count}]: ${page_title:-${page_url}}"

        if render_page_to_pdf "$page_html" "$page_pdf" "$print_css" "$page_url" "$work_dir" "$cleaner_script"; then
            pdf_parts+=("$page_pdf")
            print "${page_title}\t${page_url}" >> "$toc_entries"
        else
            warn "Failed to render: ${page_url}"
        fi

        (( render_num++ ))
    done < "$page_list"

    if (( ${#pdf_parts} == 0 )); then
        fatal "No pages could be rendered to PDF." $E_SOFTWARE
    fi

    # ---- Generate cover page ----
    local cover_pdf="${work_dir}/cover.pdf"
    local site_title
    # Use the title of the first page as the manual title
    site_title=$(head -1 "$toc_entries" | cut -f1)
    [[ -z "$site_title" ]] && site_title="Web Manual"

    local gen_date
    zmodload -F zsh/datetime b:strftime
    strftime -s gen_date '%B %d, %Y'

    info "Generating cover page..."
    generate_cover_page "$site_title" "$seed_url" "$gen_date" "$cover_pdf" "$work_dir"

    # ---- Generate TOC page ----
    local toc_pdf="${work_dir}/toc.pdf"
    info "Generating table of contents..."
    generate_toc_page "$toc_entries" "$toc_pdf" "$work_dir"

    # ---- Merge all PDFs ----
    local merged_pdf="${work_dir}/merged.pdf"
    local -a all_pdfs=("$cover_pdf" "$toc_pdf" "${pdf_parts[@]}")

    info "Merging ${#all_pdfs} PDF(s)..."
    pdfunite "${all_pdfs[@]}" "$merged_pdf"

    # ---- OCR for searchability ----
    local final_pdf="$merged_pdf"
    if [[ $NO_OCR == false ]]; then
        info "Running OCR for searchability (this may take a while)..."
        local ocr_pdf="${work_dir}/ocr.pdf"
        if ocrmypdf --skip-text --optimize 1 -q "$merged_pdf" "$ocr_pdf" 2>/dev/null; then
            final_pdf="$ocr_pdf"
        else
            warn "OCR processing failed; using non-OCR version"
        fi
    fi

    # ---- Copy to output ----
    cp "$final_pdf" "$OUTPUT_FILE" || fatal "Cannot write output file: ${OUTPUT_FILE}" $E_CANTCREAT

    info "Manual generated: ${OUTPUT_FILE} (${#pdf_parts} pages)"
    return $E_SUCCESS
}

# ==============================================================================
# INITIALIZATION AND ENTRY POINT
# ==============================================================================

init() {
    emulate -L zsh
    init_colors
    setup_traps
    debug "Initializing ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    debug "Running on: $(uname -s) $(uname -r)"
    debug "Zsh version: ${ZSH_VERSION}"
    debug "Script directory: ${SCRIPT_DIR}"
}

_main() {
    emulate -L zsh
    init
    parse_arguments "$@"
    validate_dependencies
    validate_arguments
    {
        main
    } always {
        :
    }
    exit $E_SUCCESS
}

# ==============================================================================
# SOURCE GUARD AND EXECUTION
# ==============================================================================

if [[ "${(%):-%x}" == "$0" ]] || [[ -n "${ZSH_SCRIPT:-}" ]]; then
    _main "$@"
fi

# ==============================================================================
# ZSH COMPLETION FUNCTION SCAFFOLD
# ==============================================================================
# To enable command completion, create a file named _webmanual in your fpath:
#
# #compdef webmanual
#
# _webmanual() {
#     local -a options
#     options=(
#         '(-h --help)'{-h,--help}'[Show help message]'
#         '(-V --version)'{-V,--version}'[Show version]'
#         '*'{-v,--verbose}'[Increase verbosity]'
#         '(-q --quiet)'{-q,--quiet}'[Suppress output]'
#         '(-n --dry-run)'{-n,--dry-run}'[Dry run mode]'
#         '(-d --debug)'{-d,--debug}'[Enable debug mode]'
#         '(-o --output)'{-o,--output}'[Output PDF file]:output file:_files -g "*.pdf"'
#         '(-D --depth)'{-D,--depth}'[Crawl depth]:depth:'
#         '(-M --max-pages)'{-M,--max-pages}'[Max pages]:max:'
#         '(-s --scope)'{-s,--scope}'[Scope prefix URL]:scope URL:'
#         '--no-ocr[Skip OCR step]'
#         '--timeout[HTTP timeout]:seconds:'
#     )
#
#     _arguments -s $options '*:URL:'
# }
#
# _webmanual "$@"
