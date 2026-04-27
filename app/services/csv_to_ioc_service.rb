require "securerandom"
require "rexml/document"

class CsvToIocService
  HASH_PATTERNS = {
    md5:    { regex: /\A[0-9a-f]{32}\z/i,  label: "MD5",    search: "FileItem/Md5sum",    content_type: "md5" },
    sha1:   { regex: /\A[0-9a-f]{40}\z/i,  label: "SHA-1",  search: "FileItem/Sha1sum",   content_type: "sha1" },
    sha256: { regex: /\A[0-9a-f]{64}\z/i,  label: "SHA-256", search: "FileItem/Sha256sum", content_type: "sha256" },
    sha512: { regex: /\A[0-9a-f]{128}\z/i, label: "SHA-512", search: "FileItem/Sha512sum", content_type: "sha512" }
  }.freeze

  Result = Struct.new(:xml, :entries, :filename, :error, keyword_init: true)

  def self.call(csv_file, ioc_name: "Indicators")
    new(csv_file, ioc_name: ioc_name).call
  end

  def initialize(csv_file, ioc_name: "Indicators")
    @csv_file = csv_file
    @ioc_name = ioc_name
  end

  def call
    entries = parse_csv
    return Result.new(error: "No valid hash values found in CSV.") if entries.empty?

    xml = build_ioc(entries)
    Result.new(xml: xml, entries: entries, filename: "#{@ioc_name.parameterize}.ioc")
  rescue CSV::MalformedCSVError => e
    Result.new(error: "Invalid CSV: #{e.message}")
  end

  private

  def parse_csv
    entries = []
    content = @csv_file.read.force_encoding("UTF-8")
    CSV.parse(content, liberal_parsing: true).each do |row|
      row.each do |cell|
        next if cell.nil?
        value = cell.strip
        type = detect_type(value)
        entries << { value: value, type: type } if type
      end
    end
    entries.uniq { |e| e[:value].downcase }
  end

  def detect_type(value)
    HASH_PATTERNS.each do |key, config|
      return key if value.match?(config[:regex])
    end
    nil
  end

  def build_ioc(entries)
    doc = REXML::Document.new
    doc << REXML::XMLDecl.new("1.0", "utf-8")

    ioc = doc.add_element("ioc", {
      "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
      "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
      "id"         => SecureRandom.uuid,
      "last-modified" => Time.now.utc.iso8601,
      "xmlns"      => "http://schemas.mandiant.com/2010/ioc"
    })

    ioc.add_element("short_description").text = @ioc_name
    ioc.add_element("authored_by").text = "csv-to-ioc"
    ioc.add_element("authored_date").text = Time.now.utc.iso8601
    ioc.add_element("links")

    definition = ioc.add_element("definition")
    root_indicator = definition.add_element("Indicator", { "id" => SecureRandom.uuid, "operator" => "OR" })

    entries.each do |entry|
      config = HASH_PATTERNS[entry[:type]]
      item = root_indicator.add_element("IndicatorItem", {
        "id"        => SecureRandom.uuid,
        "condition" => "is"
      })
      item.add_element("Context", {
        "document" => "FileItem",
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
