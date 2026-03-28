# Scope Detection

Scope detection is the mechanism that determines which linked pages are "part of the manual" and which are external. It is the core heuristic that makes `webmanual` produce focused, coherent manuals rather than crawling an entire website.

## How It Works

Given a seed URL, the scope prefix is computed as:

```
scheme://host/path-up-to-last-slash/
```

The algorithm:

1. Parse the seed URL into scheme, host, and path components.
2. Strip any trailing `index.html` or `index.htm` from the path.
3. If the path does not end with `/`, take the directory portion (everything up to and including the last `/`).
4. Reconstruct the scope as `scheme://host/directory-path/`.

A discovered link is **in scope** if and only if its full URL starts with the scope prefix string.

## Examples

### Seed: `https://docs.example.com/guide/getting-started`

Computed scope: `https://docs.example.com/guide/`

| URL | In Scope | Reason |
|-----|----------|--------|
| `https://docs.example.com/guide/advanced` | Yes | Starts with scope prefix |
| `https://docs.example.com/guide/api/reference` | Yes | Nested under scope prefix |
| `https://docs.example.com/guide/` | Yes | Exact match of scope prefix |
| `https://docs.example.com/blog/post` | No | `/blog/` is outside `/guide/` |
| `https://docs.example.com/` | No | Root is above the scope prefix |
| `https://other.example.com/guide/` | No | Different host |
| `http://docs.example.com/guide/page` | No | Different scheme (http vs https) |

### Seed: `https://docs.example.com/guide/`

Computed scope: `https://docs.example.com/guide/` (unchanged -- path already ends with `/`)

### Seed: `https://docs.example.com/guide/index.html`

Computed scope: `https://docs.example.com/guide/` (index.html is stripped first)

## Overriding Scope

Use `-s`/`--scope` to manually set the scope prefix:

```zsh
# Widen scope to the entire docs site
./webmanual.zsh -s https://docs.example.com/ https://docs.example.com/guide/intro

# Narrow scope to a specific sub-section
./webmanual.zsh -s https://docs.example.com/guide/v2/ https://docs.example.com/guide/v2/overview

# Cross-path scope (include sibling sections)
./webmanual.zsh -s https://docs.example.com/reference/ https://docs.example.com/reference/api/endpoints
```

The scope override is used as-is -- it is not further processed. Ensure it ends with `/` if you want prefix matching on a directory boundary.

## Edge Cases

**Single-page sites**: If the seed URL has no sub-path (e.g., `https://example.com/`), the scope prefix is `https://example.com/`, which matches the entire domain. Use `-D 0` to restrict to just the seed page, or set a narrower scope with `-s`.

**Query strings and fragments**: Fragments (`#section`) are stripped during link normalization. Query strings are preserved in URLs but do not affect scope matching -- a URL with `?page=2` will match the scope prefix normally.

**Trailing slashes**: The scope prefix always ends with `/`. URLs without trailing slashes still match: `https://docs.example.com/guide/page` starts with `https://docs.example.com/guide/`.

**Redirects**: curl follows redirects (`-L`), so the final URL after redirects is what gets checked and stored. If a site redirects from `http://` to `https://`, and your scope uses `https://`, redirected pages will match correctly.
