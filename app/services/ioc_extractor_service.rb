require "securerandom"
require "rexml/document"

class IocExtractorService
  # OpenIOC 1.0 standard indicator definitions — ordered so longer/stricter patterns
  # run first (sha512 before sha256 before sha1 before md5) to prevent false partial
  # matches at word boundaries.
  INDICATORS = {
    sha512: {
      regex:        /\b([0-9a-f]{128})\b/i,
      search:       "FileItem/Sha512sum",
      document:     "FileItem",
      content_type: "sha512",
      label:        "SHA-512",
      group:        :hash
    },
    sha256: {
      regex:        /\b([0-9a-f]{64})\b/i,
      search:       "FileItem/Sha256sum",
      document:     "FileItem",
      content_type: "sha256",
      label:        "SHA-256",
      group:        :hash
    },
    sha1: {
      regex:        /\b([0-9a-f]{40})\b/i,
      search:       "FileItem/Sha1sum",
      document:     "FileItem",
      content_type: "sha1",
      label:        "SHA-1",
      group:        :hash
    },
    md5: {
      regex:        /\b([0-9a-f]{32})\b/i,
      search:       "FileItem/Md5sum",
      document:     "FileItem",
      content_type: "md5",
      label:        "MD5",
      group:        :hash
    },
    ipv4: {
      regex:        /\b((?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?))\b/,
      search:       "PortItem/remoteIP",
      document:     "PortItem",
      content_type: "IP",
      label:        "IPv4",
      group:        :network
    },
    ipv6: {
      regex:        /\b((?:[0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4})\b/i,
      search:       "PortItem/remoteIP",
      document:     "PortItem",
      content_type: "IP",
      label:        "IPv6",
      group:        :network
    },
    url: {
      regex:        %r{\b(https?://[^\s"'<>\[\]{}\|\\^`\r\n]+)}i,
      search:       "Network/URI",
      document:     "Network",
      content_type: "string",
      label:        "URL",
      group:        :network
    },
    email: {
      regex:        /\b([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})\b/,
      search:       "Email/From",
      document:     "Email",
      content_type: "string",
      label:        "Email",
      group:        :network
    },
    domain: {
      # Common TLDs to limit false positives; matches standalone domains not embedded in URLs
      regex:        /(?<![\/\w@])((?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+(?:com|net|org|edu|gov|mil|io|co|uk|ru|cn|de|fr|br|in|jp|info|biz|onion|xyz|top|club|site|online|tech|live|app|dev|cloud|ai|gg|tv|me|cc|us|ca|au|nl|se|no|fi|dk|pl|es|pt|it|be|ch|at|nz|sg|hk|tw|kr|th|id|vn|pk|sa|ae|il|tr|ua))\b/i,
      search:       "Network/DNS",
      document:     "Network",
      content_type: "string",
      label:        "Domain",
      group:        :network
    },
    filepath_win: {
      regex:        /([A-Za-z]:\\(?:[^\\\/\:\*\?"<>\|\r\n\t]+\\)*[^\\\/\:\*\?"<>\|\r\n\t ]*)/,
      search:       "FileItem/FullPath",
      document:     "FileItem",
      content_type: "string",
      label:        "Windows Path",
      group:        :filesystem
    },
    filepath_unix: {
      # Negative lookbehind for ':' excludes '://' in URLs; (?!\/) excludes UNC '//...'
      regex:        /(?<!:)(\/(?!\/)(?:[^\s"'<>|\\:\r\n]+\/)+[^\s"'<>|\\:\r\n]*)/,
      search:       "FileItem/FullPath",
      document:     "FileItem",
      content_type: "string",
      label:        "Unix Path",
      group:        :filesystem
    },
    registry_key: {
      regex:        /\b(HK(?:EY_LOCAL_MACHINE|EY_CURRENT_USER|EY_CLASSES_ROOT|EY_USERS|EY_CURRENT_CONFIG|LM|CU|CR)\\[^\s"'<>\r\n,;]+)/i,
      search:       "RegistryItem/KeyPath",
      document:     "RegistryItem",
      content_type: "string",
      label:        "Registry Key",
      group:        :registry
    },
    mutex: {
      regex:        /\bMutex(?:Name)?[\s:=]+"?([^\s"',;\r\n]{4,})"?/i,
      search:       "ProcessItem/HandleList/Handle/Name",
      document:     "ProcessItem",
      content_type: "string",
      label:        "Mutex",
      group:        :process
    },
    service_name: {
      regex:        /\bServiceName[\s:=]+"?([a-zA-Z0-9_\-\.]{3,64})"?/i,
      search:       "ServiceItem/Name",
      document:     "ServiceItem",
      content_type: "string",
      label:        "Service Name",
      group:        :process
    }
  }.freeze

  # 11 000 chars — conservative buffer below the 12 288 platform limit
  MAX_IOC_BYTES = 11_000

  Result = Struct.new(:files, :entries, :error, keyword_init: true)
  # files: [{ xml: String, filename: String, entries: Array }]

  def self.call(text, ioc_name: "Indicators", force_single: false)
    new(text, ioc_name: ioc_name, force_single: force_single).call
  end

  def self.rebuild(entries, ioc_name: "Indicators", force_single: false)
    svc    = new("", ioc_name: ioc_name, force_single: force_single)
    chunks = force_single ? [entries] : svc.send(:split_into_chunks, entries)
    base   = ioc_name.parameterize

    files = chunks.each_with_index.map do |chunk, i|
      suffix   = chunks.size > 1 ? "-part#{i + 1}of#{chunks.size}" : ""
      filename = "#{base}#{suffix}.ioc"
      { xml: svc.send(:build_ioc, chunk), filename: filename, entries: chunk }
    end

    Result.new(files: files, entries: entries)
  end

  def initialize(text, ioc_name: "Indicators", force_single: false)
    @text         = text
    @ioc_name     = ioc_name
    @force_single = force_single
  end

  def call
    entries = extract_all_indicators
    return Result.new(error: "No IOC indicators found in the document.") if entries.empty?

    chunks = @force_single ? [entries] : split_into_chunks(entries)
    base   = @ioc_name.parameterize

    files = chunks.each_with_index.map do |chunk, i|
      suffix   = chunks.size > 1 ? "-part#{i + 1}of#{chunks.size}" : ""
      filename = "#{base}#{suffix}.ioc"
      { xml: build_ioc(chunk), filename: filename, entries: chunk }
    end

    Result.new(files: files, entries: entries)
  end

  private

  # Replace OCR symbol confusables then clean each whitespace-separated token:
  #   1. Strip non-hex chars from both ends
  #   2. Remove embedded non-hex chars (≤3) if result is a valid hash length
  #   3. Pure-hex token that is exactly 1 char too long → try dropping first or last char
  def preprocess_for_hashes(text)
    cleaned = text.gsub(/[#{Regexp.escape(OCR_CHAR_MAP.keys.join)}]/, OCR_CHAR_MAP)
    cleaned.gsub(/\S+/) { |token| clean_hash_token(token) }
  end

  def clean_hash_token(token)
    # Strip non-hex chars from both ends
    stripped = token.sub(/\A[^0-9a-fA-F]+/, "").sub(/[^0-9a-fA-F]+\z/, "")
    return stripped if valid_hash_string?(stripped)

    # Remove ALL embedded non-hex chars (tolerate up to 3 noise chars)
    hex_only = token.gsub(/[^0-9a-fA-F]/, "")
    noise    = token.length - hex_only.length
    return hex_only if noise <= 3 && valid_hash_string?(hex_only)

    # Pure hex but exactly 1 char too long (spurious prefix/suffix char)
    if token.match?(/\A[0-9a-fA-F]+\z/i)
      [token[1..], token[0..-2]].each do |candidate|
        return candidate if valid_hash_string?(candidate)
      end
    end

    token
  end

  def valid_hash_string?(s)
    s && [32, 40, 64, 128].include?(s.length) && s.match?(/\A[0-9a-f]+\z/i)
  end

  def split_into_chunks(entries)
    full_xml = build_ioc(entries)
    return [entries] if full_xml.bytesize <= MAX_IOC_BYTES

    # Estimate how many entries fit within the byte limit
    overhead          = build_ioc([]).bytesize
    bytes_per_entry   = [(full_xml.bytesize - overhead).to_f / entries.size, 1].max
    chunk_size        = [(( MAX_IOC_BYTES - overhead) / bytes_per_entry).floor, 1].max

    entries.each_slice(chunk_size).map(&:itself)
  end

  HASH_TYPES = %i[sha512 sha256 sha1 md5].freeze

  # OCR confusables that appear as non-hex chars inside what should be hex hashes
  OCR_CHAR_MAP = {
    "#" => "f",  # f misread as #
    "£" => "f",  # f misread as £
    "¥" => "f",  # f misread as ¥
    "@" => "0",  # 0 misread as @
    "s" => "8",  # 8 misread as s (confirmed: hash ending in fsd → f8d)
    "l" => "1",  # 1 misread as l
    "§" => "5",
    "©" => "c",
    "°" => "0",
    "O" => "0",
    "o" => "0",
    "ø" => "0",
    "Ø" => "0",
  }.freeze

  def extract_all_indicators
    seen = {}
    entries = []

    hash_text         = preprocess_for_hashes(@text)
    text_without_urls = @text.gsub(INDICATORS[:url][:regex], "")

    INDICATORS.each do |type, config|
      scan_text = if HASH_TYPES.include?(type)
                    hash_text
                  elsif type == :domain || type == :filepath_unix
                    text_without_urls
                  else
                    @text
                  end

      scan_text.scan(config[:regex]) do |match|
        value = match.first.strip
        next if value.empty?
        key = "#{type}:#{value.downcase}"
        next if seen[key]

        seen[key] = true
        entries << { value: value, type: type }
      end
    end

    entries
  end

  def build_ioc(entries)
    doc = REXML::Document.new
    doc << REXML::XMLDecl.new("1.0", "utf-8")

    ioc = doc.add_element("ioc", {
      "xmlns:xsi"     => "http://www.w3.org/2001/XMLSchema-instance",
      "xmlns:xsd"     => "http://www.w3.org/2001/XMLSchema",
      "id"            => SecureRandom.uuid,
      "last-modified" => Time.now.utc.iso8601,
      "xmlns"         => "http://schemas.mandiant.com/2010/ioc"
    })

    ioc.add_element("short_description").text = @ioc_name
    ioc.add_element("authored_by").text        = "csv-to-ioc"
    ioc.add_element("authored_date").text      = Time.now.utc.iso8601
    ioc.add_element("links")

    root_indicator = ioc.add_element("definition")
                        .add_element("Indicator", { "id" => SecureRandom.uuid, "operator" => "OR" })

    entries.each do |entry|
      config = INDICATORS[entry[:type]]
      item = root_indicator.add_element("IndicatorItem", {
        "id"        => SecureRandom.uuid,
        "condition" => "is"
      })
      item.add_element("Context", {
        "document" => config[:document],
        "search"   => config[:search],
        "type"     => "mir"
      })
      item.add_element("Content", { "type" => config[:content_type] }).text = entry[:value]
    end

    formatter = REXML::Formatters::Pretty.new(2)
    formatter.compact = true
    output = String.new
    formatter.write(doc, output)
    output
  end
end
