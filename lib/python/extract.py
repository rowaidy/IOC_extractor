#!/usr/bin/env python3
"""Extract text from any file using docling with Tesseract OCR."""

import sys
import json
import os
import re

TEXT_EXTENSIONS = {
    ".txt", ".csv", ".tsv", ".log", ".md", ".json",
    ".xml", ".html", ".htm", ".ioc", ".yaml", ".yml",
    ".ini", ".cfg", ".conf", ".toml", ".nfo", ".rtf",
}


def extract_text(file_path: str) -> str:
    ext = os.path.splitext(file_path)[1].lower()

    if ext in TEXT_EXTENSIONS:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()

    try:
        from docling.document_converter import DocumentConverter, PdfFormatOption, ImageFormatOption
        from docling.datamodel.pipeline_options import PdfPipelineOptions, TesseractCliOcrOptions
        from docling.datamodel.base_models import InputFormat

        ocr_options = TesseractCliOcrOptions(force_full_page_ocr=True)

        pipeline_options = PdfPipelineOptions()
        pipeline_options.do_ocr = True
        pipeline_options.do_table_structure = True
        pipeline_options.ocr_options = ocr_options

        converter = DocumentConverter(
            format_options={
                InputFormat.PDF:   PdfFormatOption(pipeline_options=pipeline_options),
                InputFormat.IMAGE: ImageFormatOption(pipeline_options=pipeline_options),
            }
        )

        result = converter.convert(file_path)
        text = result.document.export_to_markdown()

        text = re.sub(r'<!--\s*image\s*-->', '', text)
        text = re.sub(r'!\[.*?\]\(.*?\)', '', text)

        return text.strip()

    except ImportError:
        raise RuntimeError("docling is not installed. Run: pip install docling")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"success": False, "error": "No file path provided"}))
        sys.exit(1)

    file_path = sys.argv[1]
    try:
        text = extract_text(file_path)
        if not text.strip():
            print(json.dumps({
                "success": False,
                "error": "No text extracted. Ensure tesseract-ocr is installed: sudo apt install tesseract-ocr"
            }))
            sys.exit(1)
        print(json.dumps({"success": True, "text": text}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e), "text": ""}))
        sys.exit(1)
