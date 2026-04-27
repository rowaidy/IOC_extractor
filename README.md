# Technical Proposal: IOC Extractor

**Document version:** 1.0  
**Date:** April 2026  
**Author:** Khalid Abuelhassan

---

## 1. Introduction

Threat intelligence sharing is a cornerstone of modern cyber-defence. Security teams routinely encounter Indicators of Compromise (IOCs) — file hashes, IP addresses, domain names, URLs, file paths, registry keys, and more — embedded in PDF reports, Word documents, spreadsheets, images, and plain-text files. Extracting these indicators manually is time-consuming and error-prone, and preparing them in the format required by most SIEM, EDR, and threat-intelligence platforms (OpenIOC 1.0 XML) introduces additional friction.

**IOC Extractor** is a web-based tool that eliminates this overhead. Analysts upload any document in any common format; the system automatically identifies all IOC indicators present in the document and delivers a standards-compliant OpenIOC 1.0 XML file ready for immediate platform import — without manual copy-paste or format conversion.

---

## 2. Solution Summary

IOC Extractor is a self-hosted Ruby on Rails web application that accepts file uploads, performs text extraction (including OCR for scanned documents and images), detects all indicator types defined in the OpenIOC 1.0 standard, and produces a downloadable IOC file or ZIP bundle.

The analyst workflow is three steps:

1. **Upload** — drag-drop or browse any file (PDF, DOCX, PPTX, XLSX, CSV, PNG, JPG, TXT, and more).
2. **Review** — the results page shows all extracted indicators grouped by category; values can be edited or deleted inline before download.
3. **Download** — receive a single `.ioc` XML file or, for large indicator sets, a ZIP bundle of multiple files.

The solution runs entirely on-premises. No indicator data leaves the organisation's environment.

---

## 3. Solution Design

### 3.1 Architecture Overview

```
Browser
  │
  │  POST /convert (multipart upload)
  ▼
Rails Application (IocController)
  │
  ├─► DocumentExtractor
  │     ├─ Text files  ──────────────────► read directly as UTF-8
  │     └─ Binary / Image files ─────────► Python subprocess (docling + Tesseract OCR)
  │                                              │
  │                                              ▼
  │                                         Extracted text (Markdown)
  │
  ├─► IocExtractorService
  │     ├─ OCR pre-processing (confusable char normalisation)
  │     ├─ Regex scan for all 14 indicator types
  │     ├─ De-duplication
  │     └─ Chunking (≤ 11 000 bytes per file)
  │
  ├─► File system  (tmp/ioc_files/<token>.ioc  or  <token>.zip)
  │
  └─► Browser  ◄── GET /download/:token  (preview + download)
```

### 3.2 Text Extraction Layer (`DocumentExtractor`)

Files are routed by extension:

| Class | Extensions | Method |
|---|---|---|
| Plain text | `.txt .csv .tsv .log .md .json .xml .html .htm .ioc .yaml .yml .ini .cfg .conf .toml .nfo .rtf .eml .msg` | Read directly as UTF-8 |
| Binary documents | `.pdf .docx .doc .pptx .ppt .xlsx .xls .odt .odp .ods .epub` | docling Python library |
| Images | `.png .jpg .jpeg .bmp .tiff .tif .gif .webp` | docling + Tesseract OCR |
| Unknown | — | Try UTF-8 read; fall back to docling |

For OCR input, docling is configured with `force_full_page_ocr=True` and `TesseractCliOcrOptions` to ensure all content is processed, including scanned PDFs treated as images.

### 3.3 OCR Post-Processing

Tesseract frequently misreads characters inside hex strings. A two-stage cleaning pipeline corrects these before indicator extraction:

1. **Character confusable map** — maps known Tesseract misreads to their correct hex equivalents (e.g., `#→f`, `@→0`, `s→8`, `l→1`, `O→0`).
2. **Token-level cleaning** — for each whitespace-delimited token: strip non-hex leading/trailing chars; remove ≤3 embedded noise characters if the result matches a valid hash length (32 / 40 / 64 / 128 hex characters); handle pure-hex tokens that are exactly one character too long.

### 3.4 Indicator Extraction Layer (`IocExtractorService`)

Indicators are extracted via ordered regex scanning. Longer/more specific patterns run first (SHA-512 before SHA-256 before SHA-1 before MD5) to prevent partial false matches. URL-bearing text is pre-stripped before domain and Unix-path scanning to eliminate double-counting.

### 3.5 IOC Generation and Chunking

Extracted entries are serialised into OpenIOC 1.0 XML using the Mandiant schema (`http://schemas.mandiant.com/2010/ioc`). When the resulting file exceeds 11 000 bytes (conservative buffer below the 12 288-character platform import limit), entries are distributed across multiple files. Multiple files are packaged as a ZIP archive for a single download action.

### 3.6 Session and Storage Model

- Session cookies store only a random URL-safe token (16 bytes). No indicator data is held in the session, preventing `CookieOverflow` errors on large indicator sets.
- Generated files, metadata (JSON), and raw extracted text are written to `tmp/ioc_files/<token>.*` on the application server.
- Files are not transmitted to any third-party service.

---

## 4. Application Features

| Feature | Detail |
|---|---|
| **Universal file input** | Accepts plain text, rich documents (PDF, DOCX, PPTX, XLSX), images, and more via drag-and-drop or file browser |
| **14 OpenIOC indicator types** | MD5, SHA-1, SHA-256, SHA-512, IPv4, IPv6, URL, Email, Domain, Windows Path, Unix Path, Registry Key, Mutex, Service Name |
| **OCR support** | Scanned PDFs and images processed via Tesseract OCR with automated confusable-character correction |
| **Inline editing** | Extracted indicator values are editable directly on the results page before download |
| **Inline deletion** | Individual indicators can be removed; empty groups collapse automatically |
| **Output format control** | Analyst chooses between auto-split (multiple files, each ≤ 11 000 chars) or single-file output at upload time and again on the results page |
| **ZIP bundle** | Multi-file results delivered as a single ZIP download |
| **Live indicator count** | Total indicator count updates in real time as items are edited or deleted |
| **Raw text debug panel** | Results page exposes the first 3 000 characters of extracted text for OCR verification |
| **XML preview** | First 30 lines of the generated IOC XML shown on the results page |
| **Processing overlay** | Animated step-by-step progress indicator shown during document conversion |
| **On-premises** | No data leaves the server; fully self-hosted |
| **Standards-compliant output** | OpenIOC 1.0 XML with Mandiant namespace, UUIDs, authored-by, and timestamp fields |

---

## 5. Software Dependencies

### 5.1 Ruby / Rails Stack

| Package | Version | Purpose |
|---|---|---|
| Ruby | 3.4.x | Runtime |
| Rails | 8.1.x | Web framework |
| Propshaft | latest | Asset pipeline |
| Hotwire (Turbo + Stimulus) | latest | Front-end reactivity |
| rexml | stdlib | OpenIOC XML generation |
| rubyzip | latest | ZIP bundle packaging |
| sqlite3 | latest | Session / cache backend (Solid Cache) |
| rubocop-rails-omakase | latest | Linting |

### 5.2 Front-End

| Package | Version | Purpose |
|---|---|---|
| Bootstrap | 5.x | UI framework |
| Bootstrap Icons | latest | Icon set |
| Sass | latest | SCSS compilation |
| PostCSS + Autoprefixer | latest | CSS post-processing |
| Node.js | 24.x | Build toolchain |
| importmap-rails | latest | Browser JS module loading (no bundler) |

### 5.3 Python Stack

| Package | Version | Purpose |
|---|---|---|
| Python | 3.10+ | Subprocess runtime for document extraction |
| docling | 2.x | PDF, DOCX, PPTX, XLSX, image parsing |
| Tesseract OCR | 4.x+ (system) | OCR engine used by docling |

Python dependencies are installed in a virtual environment (`~/docling-venv`) to comply with Debian/Ubuntu externally-managed-environment restrictions. The `DOCLING_PYTHON` environment variable points the Rails application at the venv binary.

---

## 6. Hardware Requirements

These are minimum recommended specifications for a single-server deployment handling moderate analyst workloads (< 50 concurrent users, document sizes up to ~50 MB).

| Component | Minimum | Recommended |
|---|---|---|
| **CPU** | 2 cores | 4+ cores |
| **RAM** | 4 GB | 8 GB |
| **Storage** | 20 GB | 50 GB SSD |
| **Network** | 100 Mbps | 1 Gbps |

**Notes:**
- Tesseract OCR and docling are CPU-intensive for large scanned PDFs or high-resolution images. Additional cores reduce per-request latency significantly.
- RAM requirement increases with docling's ML model loading (~1–2 GB resident after first use). 8 GB is strongly preferred in production.
- Temporary files accumulate in `tmp/ioc_files/`. A cleanup job (cron or Solid Queue) should be scheduled for production deployments. Storage estimate assumes a 7-day retention window.
- GPU is not required; docling operates in CPU-only mode.

---

## 7. Software Requirements

### 7.1 Server Operating System

- **Supported:** Ubuntu 22.04 LTS / 24.04 LTS, Debian 12, RHEL 9 / Rocky Linux 9
- **Recommended:** Ubuntu 22.04 LTS or later

### 7.2 Required System Packages

```bash
# Ruby runtime
rbenv or rvm (Ruby 3.4.x)

# Node.js (build toolchain)
Node.js 24.x (via NodeSource or nvm)

# Tesseract OCR engine
sudo apt install tesseract-ocr tesseract-ocr-eng

# Python venv (for docling)
sudo apt install python3 python3-venv python3-pip

# SQLite (default database)
sudo apt install libsqlite3-dev
```

### 7.3 Python Environment Setup

```bash
python3 -m venv ~/docling-venv
~/docling-venv/bin/pip install docling
```

Set the environment variable in the application's process environment:

```bash
DOCLING_PYTHON=/home/<user>/docling-venv/bin/python3
```

### 7.4 Application Setup

```bash
bundle install
npm install
npm run build:css
bin/rails db:prepare
bin/rails assets:precompile   # production only
bin/rails server              # development
# or
bin/dev                       # development (web + CSS watcher)
```

### 7.5 Docker Installation (Recommended)

Docker is the easiest way to run IOC Extractor in production. All dependencies — Ruby, Python, docling, Tesseract OCR — are built into the image.

**Prerequisites:**
- Docker Engine 24+ and Docker Compose v2

**Step 1 — Clone the repository**

```bash
git clone https://github.com/rowaidy/IOC_extractor.git
cd IOC_extractor
```

**Step 2 — Configure environment**

```bash
cp .env.example .env
```

The `.env.example` file ships with a pre-generated `SECRET_KEY_BASE`. No editing required for a standard deployment. The application does not require `config/master.key` or `RAILS_MASTER_KEY`.

**Step 3 — Build and start**

```bash
docker compose up --build
```

First build takes 10–20 minutes — docling pulls ~2 GB of ML dependencies (PyTorch, Transformers). Subsequent builds use the Docker layer cache and are much faster.

**Step 4 — Access the application**

Open [http://localhost](http://localhost) in a browser.

**Running in the background**

```bash
docker compose up --build -d      # detached mode
docker compose logs -f            # follow logs
docker compose down               # stop
```

**Updating to a new version**

```bash
git pull
docker compose up --build -d
```

**Persistent data**

Two named Docker volumes are created automatically:

| Volume | Contents |
|---|---|
| `ioc_files` | Generated `.ioc` and `.zip` files |
| `sqlite_data` | SQLite databases (sessions, cache, queue) |

Data survives container restarts and rebuilds. To wipe all data:

```bash
docker compose down -v
```

**Environment variables**

| Variable | Required | Description |
|---|---|---|
| `SECRET_KEY_BASE` | Yes | Rails session signing secret (pre-generated in `.env.example`) |
| `RAILS_ENV` | No | Defaults to `production` inside the image |
| `DOCLING_PYTHON` | No | Defaults to `/rails/docling-venv/bin/python3` |

### 7.6 Production Deployment (Traditional)

The application ships with Kamal configuration (`.kamal/`) for container-based deployment. For traditional server deployment:

- **Web server:** Puma (bundled with Rails 8)
- **Reverse proxy:** Nginx or Caddy (SSL termination, static file serving)
- **Process manager:** systemd or Foreman
- **Environment variables required:**

| Variable | Description |
|---|---|
| `SECRET_KEY_BASE` | Rails secret key (production) |
| `RAILS_ENV` | Set to `production` |
| `DOCLING_PYTHON` | Absolute path to venv Python binary |

### 7.7 Browser Support

Any modern browser with ES2020 support:

| Browser | Minimum version |
|---|---|
| Chrome / Edge | 90+ |
| Firefox | 88+ |
| Safari | 14+ |

---

*IOC Extractor — internal technical proposal — confidential*
