# Installation Guide

## Prerequisites

### Shell

`webmanual` is a native **ZSH** script. It requires **zsh 5.0 or later**.

Check your version:

```zsh
zsh --version
```

macOS ships with zsh as the default shell since Catalina (10.15). On Linux, install it from your package manager if not already present.

### Python 3

Python 3 is required for URL parsing, link extraction, and as the runtime for WeasyPrint.

```zsh
python3 --version
```

Any Python 3.8+ release will work. macOS includes Python 3 via Xcode Command Line Tools; most Linux distributions include it by default.

---

## Dependencies

### Required

| Tool | Purpose | Provided By |
|------|---------|-------------|
| **curl** | HTTP fetching (pages + content-type detection) | System (macOS, most Linux) |
| **Python 3** | URL parsing, HTML link extraction | System or package manager |
| **WeasyPrint** | HTML-to-PDF rendering engine | `pip3 install weasyprint` |
| **pdfunite** | Merging individual PDFs into one document | Poppler utilities |
| **Ghostscript** (`gs`) | PDF post-processing | `ghostscript` package |

### Optional

| Tool | Purpose | Skip With |
|------|---------|-----------|
| **OCRmyPDF** | Adds searchable text layer to the final PDF | `--no-ocr` flag |

---

## Platform-Specific Instructions

### macOS (Homebrew)

This is the primary development platform.

```zsh
# Install system-level dependencies
brew install poppler ghostscript

# Install OCRmyPDF (optional, for searchable PDFs)
brew install ocrmypdf

# Install WeasyPrint and its Cairo/Pango dependencies
brew install cairo pango
pip3 install weasyprint
```

**Verify the installation:**

```zsh
./webmanual.zsh -d --version
```

This prints the version and, in debug mode, confirms all dependencies are found.

#### Homebrew Python vs. System Python

If you use Homebrew's Python (`brew install python`), ensure `pip3 install` targets the correct Python. You can verify with:

```zsh
which python3    # Should show /opt/homebrew/bin/python3 or similar
which weasyprint # Should be on the same prefix
```

If you use Anaconda or Miniconda, WeasyPrint installs normally via `pip3` within your active environment.

#### Apple Silicon (M1/M2/M3/M4) Notes

All dependencies support ARM64 natively via Homebrew. No Rosetta required.

---

### Linux (Debian/Ubuntu)

```bash
# System packages
sudo apt update
sudo apt install -y \
    zsh \
    curl \
    python3 python3-pip \
    poppler-utils \
    ghostscript \
    libcairo2-dev \
    libpango1.0-dev \
    libgdk-pixbuf2.0-dev \
    libffi-dev

# WeasyPrint
pip3 install weasyprint

# OCRmyPDF (optional)
sudo apt install -y ocrmypdf
```

---

### Linux (Fedora/RHEL/CentOS)

```bash
# System packages
sudo dnf install -y \
    zsh \
    curl \
    python3 python3-pip \
    poppler-utils \
    ghostscript \
    cairo-devel \
    pango-devel \
    gdk-pixbuf2-devel

# WeasyPrint
pip3 install weasyprint

# OCRmyPDF (optional)
sudo dnf install -y ocrmypdf
```

---

### Linux (Arch)

```bash
sudo pacman -S --needed \
    zsh \
    curl \
    python python-pip \
    poppler \
    ghostscript \
    cairo \
    pango

pip3 install weasyprint

# OCRmyPDF (optional)
sudo pacman -S python-ocrmypdf
```

---

## Verifying Your Installation

Run the built-in dependency check:

```zsh
./webmanual.zsh -d -n https://example.com 2>&1 | grep -E '(Found|not found)'
```

Expected output (all "Found"):

```
[DEBUG] Found required binary: curl -> /usr/bin/curl
[DEBUG] Found required binary: python3 -> /usr/bin/python3
[DEBUG] Found required binary: weasyprint -> /usr/local/bin/weasyprint
[DEBUG] Found required binary: pdfunite -> /usr/bin/pdfunite
[DEBUG] Found required binary: gs -> /usr/bin/gs
[DEBUG] Found required binary: ocrmypdf -> /usr/bin/ocrmypdf
```

If any binary shows "not found", install the corresponding package listed above.

---

## Optional Setup

### Making `webmanual` Available System-Wide

```zsh
# Option 1: Symlink to a directory on your PATH
ln -s /path/to/webmanual.zsh /usr/local/bin/webmanual

# Option 2: Add the script directory to your PATH
echo 'export PATH="/path/to/Web Manual Creator:$PATH"' >> ~/.zshrc
```

### ZSH Completion

To enable tab completion, copy the completion scaffold from the bottom of `webmanual.zsh` into a file named `_webmanual` and place it in a directory on your `$fpath`:

```zsh
# Create completion file (the scaffold is at the bottom of webmanual.zsh)
# A suitable location:
mkdir -p ~/.zsh/completions
# ... copy the _webmanual function into ~/.zsh/completions/_webmanual

# Add to fpath in ~/.zshrc (before compinit):
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

### Compiling for Faster Startup

The script is compatible with `zcompile` for faster loading:

```zsh
zcompile webmanual.zsh
```

This creates `webmanual.zsh.zwc` (zsh word code). ZSH will automatically prefer the compiled version when it exists.

---

## Troubleshooting Installation

### WeasyPrint fails to install

WeasyPrint depends on Cairo and Pango C libraries. If `pip3 install weasyprint` fails:

- **macOS**: Ensure `brew install cairo pango` completed successfully.
- **Linux**: Install the `-dev`/`-devel` packages for Cairo and Pango (see platform instructions above).

### `ocrmypdf` not found but installed

OCRmyPDF may install to a user-local `bin` directory. Check:

```zsh
python3 -m ocrmypdf --version
```

If that works but `ocrmypdf` doesn't, add the Python scripts directory to your PATH:

```zsh
export PATH="$(python3 -m site --user-base)/bin:$PATH"
```

### `pdfunite` not found

`pdfunite` is part of the Poppler utilities. The package name varies:

- macOS: `brew install poppler`
- Debian/Ubuntu: `apt install poppler-utils`
- Fedora: `dnf install poppler-utils`
- Arch: `pacman -S poppler`

### Ghostscript warnings about fonts

If Ghostscript produces font warnings during OCR, install additional font packages:

```bash
# Debian/Ubuntu
sudo apt install fonts-liberation fonts-noto

# Fedora
sudo dnf install liberation-fonts google-noto-fonts-common
```
