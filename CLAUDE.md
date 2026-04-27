# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack

- **Rails 8.1** — Propshaft (asset pipeline), Hotwire (Turbo + Stimulus), importmap
- **CSS** — Bootstrap 5 via `cssbundling-rails` + Sass. Entry: `app/assets/stylesheets/application.bootstrap.scss`
- **JS** — importmap. Entry: `app/javascript/application.js`. Bootstrap JS loaded via importmap.
- **DB** — SQLite3 with Solid Cache / Queue / Cable backends
- **Ruby** 3.4.8, **Node** 24.11.0
- **Python** — docling + Tesseract OCR for binary/image extraction. Venv at `~/docling-venv`. Set `DOCLING_PYTHON=~/docling-venv/bin/python3`.

## Dev Commands

```bash
bin/dev                            # start all processes (web + css watcher)
bin/rails server                   # web only
npm run watch:css                  # CSS watcher (compiles SCSS → builds/application.css)
npm run build:css                  # one-shot CSS compile + autoprefixer

bin/rails test                     # full test suite
bin/rails test test/path/file.rb   # single file
bin/rails test test/path/file.rb:42 # single test by line

bin/rails routes
brakeman                           # security scan
rubocop                            # linting (rubocop-rails-omakase config)
```

## CSS Build Pipeline

SCSS compiles via `sass` → `app/assets/builds/application.css`, then PostCSS + autoprefixer. Propshaft serves from `builds/`. Never edit `builds/` directly.

## Purpose and Architecture

**IOC Extractor** — users upload any file (CSV, PDF, DOCX, PPTX, XLSX, images, plain text), app extracts all IOC indicators and generates a standards-compliant OpenIOC 1.0 XML file for download.

### Request flow

1. `POST /convert` → `IocController#convert`
2. `DocumentExtractor.call(file)` returns extracted text string
3. `IocExtractorService.call(text, ioc_name:)` returns `Result` with chunked files
4. Files written to `tmp/ioc_files/<token>.ioc` (single) or `<token>.zip` (multi) + `<token>.json` (metadata)
5. Session stores only token string (avoids CookieOverflow)
6. `GET /download/:token` serves the preview page or the actual file

### DocumentExtractor (`app/services/document_extractor.rb`)

Routes by extension:
- **Text extensions** (`.txt .csv .tsv .log .md .json .xml .html .htm .ioc .yaml .yml .ini .cfg .conf .toml .nfo .rtf .eml .msg`) — read directly as UTF-8
- **Image/binary extensions** — call `lib/python/extract.py` via `Open3.capture3`
- **Unknown** — try text first, fall back to docling

`DOCLING_PYTHON` env var points at the Python binary (defaults to `python3`).

### IocExtractorService (`app/services/ioc_extractor_service.rb`)

Extracts all OpenIOC 1.0 indicator types defined in `INDICATORS` hash (ordered longest-hash-first to prevent partial matches):

| Key | OpenIOC search path | Notes |
|-----|--------------------|-|
| sha512 | `FileItem/Sha512sum` | 128 hex chars |
| sha256 | `FileItem/Sha256sum` | 64 hex chars |
| sha1 | `FileItem/Sha1sum` | 40 hex chars |
| md5 | `FileItem/Md5sum` | 32 hex chars |
| ipv4 | `PortItem/remoteIP` | strict octet validation |
| ipv6 | `PortItem/remoteIP` | |
| url | `Network/URI` | https?:// |
| email | `Email/From` | |
| domain | `Network/DNS` | common TLDs only; URL-stripped text |
| filepath_win | `FileItem/FullPath` | drive-letter paths |
| filepath_unix | `FileItem/FullPath` | URL-stripped text |
| registry_key | `RegistryItem/KeyPath` | HKLM/HKCU/etc |
| mutex | `ProcessItem/HandleList/Handle/Name` | |
| service_name | `ServiceItem/Name` | |

**OCR preprocessing** — `preprocess_for_hashes` applies `OCR_CHAR_MAP` (confusable characters that Tesseract misreads inside hex strings) then `clean_hash_token` strips/cleans noise from each token.

**Chunking** — `split_into_chunks` keeps each IOC file under `MAX_IOC_BYTES` (11,000); splits into multiple files bundled as ZIP when exceeded.

### Python extractor (`lib/python/extract.py`)

Uses docling with `TesseractCliOcrOptions(force_full_page_ocr=True)` for both PDF and IMAGE inputs. Outputs JSON `{"success": true, "text": "..."}` or `{"success": false, "error": "..."}`.

### Views

- `app/views/ioc/index.html.erb` — upload form with drag-drop (Stimulus `upload` controller)
- `app/views/ioc/download.html.erb` — indicator tables grouped by category, raw text debug panel, XML preview
- `app/views/layouts/application.html.erb` — processing overlay shown during conversion

### Key constants / limits

- `MAX_IOC_BYTES = 11_000` (platform limit is 12,288 chars)
- Session: only `session[:ioc_token]` stored (prevent CookieOverflow)
- Temp files in `tmp/ioc_files/` — not cleaned up automatically in dev
