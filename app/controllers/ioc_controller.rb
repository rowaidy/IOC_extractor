require "zip"

class IocController < ApplicationController
  TMPDIR = Rails.root.join("tmp", "ioc_files")

  def index
  end

  def convert
    unless params[:file].present?
      return redirect_to root_path, alert: "Please select a file."
    end

    ioc_name     = params[:ioc_name].presence || "Indicators"
    force_single = params[:split_mode] == "single"
    text         = DocumentExtractor.call(params[:file])
    Rails.logger.debug("[IOC] extracted text (first 1000 chars):\n#{text[0..1000]}")
    result       = IocExtractorService.call(text, ioc_name: ioc_name, force_single: force_single)

    if result.error
      snippet = text.gsub(/\s+/, " ").strip[0..300]
      msg = Rails.env.development? ? "#{result.error} | Extracted: «#{snippet}»" : result.error
      return redirect_to root_path, alert: msg
    end

    token = SecureRandom.urlsafe_base64(16)
    FileUtils.mkdir_p(TMPDIR)

    if result.files.size == 1
      File.write(TMPDIR.join("#{token}.ioc"),  result.files.first[:xml])
    else
      zip_path = TMPDIR.join("#{token}.zip")
      Zip::OutputStream.open(zip_path.to_s) do |zip|
        result.files.each do |f|
          zip.put_next_entry(f[:filename])
          zip.write(f[:xml])
        end
      end
    end

    File.write(TMPDIR.join("#{token}.json"), {
      multi:          result.files.size > 1,
      split_mode:     force_single ? "single" : "auto",
      filenames:      result.files.map { |f| f[:filename] },
      entries:        result.entries.map { |e| { value: e[:value], type: e[:type].to_s } },
      extracted_text: text[0..3000]
    }.to_json)

    session[:ioc_token] = token
    redirect_to download_path(token)

  rescue DocumentExtractor::Error => e
    redirect_to root_path, alert: e.message
  end

  def update
    token     = params[:token]
    meta_path = TMPDIR.join("#{token}.json")

    unless File.exist?(meta_path) && session[:ioc_token] == token
      return redirect_to root_path, alert: "File not found or session expired."
    end

    meta         = JSON.parse(File.read(meta_path), symbolize_names: true)
    ioc_name     = meta[:filenames].first.to_s.sub(/(-part\d+of\d+)?\.ioc$/, "").tr("-", " ").titleize.presence || "Indicators"
    force_single = (params[:split_mode].presence || meta[:split_mode]) == "single"

    entries = Array(params[:entries]).filter_map do |e|
      value = e[:value].to_s.strip
      type  = e[:type].to_s.strip.to_sym
      next if value.empty?
      next unless IocExtractorService::INDICATORS.key?(type)
      { value: value, type: type }
    end

    if entries.empty?
      return redirect_to download_path(token), alert: "Cannot save — no indicators remain."
    end

    result = IocExtractorService.rebuild(entries, ioc_name: ioc_name, force_single: force_single)

    Dir.glob(TMPDIR.join("#{token}.{ioc,zip}")).each { |f| File.delete(f) rescue nil }

    if result.files.size == 1
      File.write(TMPDIR.join("#{token}.ioc"), result.files.first[:xml])
    else
      zip_path = TMPDIR.join("#{token}.zip")
      Zip::OutputStream.open(zip_path.to_s) do |zip|
        result.files.each do |f|
          zip.put_next_entry(f[:filename])
          zip.write(f[:xml])
        end
      end
    end

    File.write(TMPDIR.join("#{token}.json"), {
      multi:          result.files.size > 1,
      split_mode:     force_single ? "single" : "auto",
      filenames:      result.files.map { |f| f[:filename] },
      entries:        result.entries.map { |e| { value: e[:value], type: e[:type].to_s } },
      extracted_text: meta[:extracted_text]
    }.to_json)

    redirect_to download_path(token), notice: "#{entries.size} indicator#{entries.size == 1 ? '' : 's'} saved."
  end

  def download
    token     = params[:token]
    meta_path = TMPDIR.join("#{token}.json")

    unless File.exist?(meta_path) && session[:ioc_token] == token
      return redirect_to root_path, alert: "File not found or session expired."
    end

    meta  = JSON.parse(File.read(meta_path), symbolize_names: true)
    multi = meta[:multi]

    if params[:format] == "file"
      if multi
        send_file TMPDIR.join("#{token}.zip"),
          filename:    "#{token[0..7]}-ioc-bundle.zip",
          type:        "application/zip",
          disposition: "attachment"
      else
        send_file TMPDIR.join("#{token}.ioc"),
          filename:    meta[:filenames].first,
          type:        "application/xml",
          disposition: "attachment"
      end
    else
      @token          = token
      @multi          = multi
      @split_mode     = meta[:split_mode].presence || "auto"
      @filenames      = meta[:filenames]
      @entries        = meta[:entries].map { |e| { value: e[:value], type: e[:type].to_sym } }
      @extracted_text = meta[:extracted_text]

      ioc_path = multi ? nil : TMPDIR.join("#{token}.ioc")
      @xml_preview = ioc_path ? File.read(ioc_path).lines.first(30).join : nil
    end
  end
end
