require "open3"

class DocumentExtractor
  PYTHON_SCRIPT = Rails.root.join("lib", "python", "extract.py").to_s.freeze
  PYTHON_BIN    = ENV.fetch("DOCLING_PYTHON", "python3").freeze

  TEXT_EXTENSIONS   = %w[.txt .csv .tsv .log .md .json .xml .html .htm .ioc
                          .yaml .yml .ini .cfg .conf .toml .nfo .rtf .eml .msg].freeze
  IMAGE_EXTENSIONS  = %w[.png .jpg .jpeg .bmp .tiff .tif .gif .webp].freeze
  BINARY_EXTENSIONS = %w[.pdf .docx .doc .pptx .ppt .xlsx .xls .odt .odp .ods .epub].freeze

  # Common OCR single-char confusables inside hex strings
  OCR_HEX_TR = { "O" => "0", "o" => "0", "I" => "1", "l" => "1", "S" => "5", "Z" => "2" }.freeze

  Error = Class.new(StandardError)

  def self.call(uploaded_file)
    new(uploaded_file).call
  end

  def initialize(uploaded_file)
    @file     = uploaded_file
    @filename = uploaded_file.original_filename.to_s
    @ext      = File.extname(@filename).downcase
  end

  def call
    if TEXT_EXTENSIONS.include?(@ext)
      read_as_text
    elsif IMAGE_EXTENSIONS.include?(@ext) || BINARY_EXTENSIONS.include?(@ext)
      extract_with_docling
    else
      begin
        read_as_text
      rescue
        extract_with_docling
      end
    end
  end

  private

  def read_as_text
    @file.read.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
  end

  # PSM modes most effective for IOC indicator lists
  TESSERACT_PSMS = %w[6 4 11 3].freeze

  def extract_image_with_tesseract
    Tempfile.create(["ioc_img", @ext.presence || ".png"]) do |tmp|
      tmp.binmode
      @file.rewind
      tmp.write(@file.read)
      tmp.flush

      combined = ""
      last_error = nil

      TESSERACT_PSMS.each do |psm|
        stdout, stderr, status = Open3.capture3(
          "tesseract", tmp.path, "stdout", "-l", "eng", "--psm", psm
        )
        if status.success? && stdout.strip.present?
          combined += "\n" + stdout
        else
          last_error = stderr.presence || "tesseract psm #{psm} failed"
        end
      end

      if combined.strip.empty?
        raise Error, "Image OCR produced no text. #{last_error || 'Check tesseract-ocr is installed.'}"
      end

      normalize_ocr_text(combined)
    end
  end

  # Fix three common Tesseract problems with hash-heavy images:
  #   1. Spaces/dashes inserted inside hex sequences
  #   2. Lines split mid-hash (continuation on next line)
  #   3. Single-character confusables (O→0, l→1, etc.)
  def normalize_ocr_text(text)
    # Step 1: collapse spaces/dashes within hex-like sequences
    # Matches runs of hex chars + confusables + whitespace/dashes long enough to be a hash fragment
    text = text.gsub(/[0-9a-fA-FOIlSZ][0-9a-fA-FOIlSZ \t\-]{18,}[0-9a-fA-FOIlSZ]/) do |m|
      collapsed = m.gsub(/[\s\-]+/, "").tr("OoIlSZ", "001155")
      [32, 40, 64, 128].include?(collapsed.length) && collapsed.match?(/\A[0-9a-f]+\z/i) ? collapsed : m
    end

    # Step 2: join adjacent lines that together form a complete hash
    # (handles mid-hash line breaks from column layouts)
    3.times do
      text = text.gsub(/([0-9a-f]{8,})\r?\n([0-9a-f]{8,})/i) do
        combined = Regexp.last_match(1) + Regexp.last_match(2)
        [32, 40, 64, 128].include?(combined.length) ? combined : Regexp.last_match(0)
      end
    end

    # Step 3: normalize OCR confusables only inside isolated hex-length tokens
    text.gsub(/\b([0-9a-fA-FOIlSZ]{32}|[0-9a-fA-FOIlSZ]{40}|[0-9a-fA-FOIlSZ]{64}|[0-9a-fA-FOIlSZ]{128})\b/) do |m|
      m.chars.map { |c| OCR_HEX_TR[c] || c }.join
    end
  end

  def extract_with_docling
    Tempfile.create(["ioc_upload", @ext.presence || ".bin"]) do |tmp|
      tmp.binmode
      @file.rewind
      tmp.write(@file.read)
      tmp.flush

      stdout, stderr, status = Open3.capture3(PYTHON_BIN, PYTHON_SCRIPT, tmp.path)

      begin
        result = JSON.parse(stdout)
        raise Error, result["error"] unless result["success"]
        result["text"]
      rescue JSON::ParserError
        raise Error, "Extraction failed: #{stderr.presence || stdout.presence || "exit #{status.exitstatus}"}"
      end
    end
  end
end
