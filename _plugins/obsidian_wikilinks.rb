# frozen_string_literal: true

# Convert Obsidian-style wikilinks to Markdown links before kramdown renders.
#
# Supported:
#   [[note]]
#   [[note|text]]
#   [[note#section]]
#   [[note#section|text]]
#
# The note key intentionally matches only the Markdown filename without the
# extension, which is the form Obsidian inserts from "Add links".
module ObsidianWikilinks
  MARKDOWN_EXTENSIONS = %w[.md .markdown .mkdown .mkdn].freeze
  WIKILINK_PATTERN = /(?<!!)\[\[([^\]\n]+)\]\]/.freeze

  module_function

  def convert(content, site, source_doc)
    in_fence = false
    fence_char = nil
    fence_length = 0

    content.each_line.map do |line|
      fence = fence_marker(line)

      if fence && !in_fence
        in_fence = true
        fence_char = fence[:char]
        fence_length = fence[:length]
        line
      elsif in_fence
        if fence && fence[:char] == fence_char && fence[:length] >= fence_length
          in_fence = false
          fence_char = nil
          fence_length = 0
        end

        line
      else
        convert_line(line, site, source_doc)
      end
    end.join
  end

  def convert_line(line, site, source_doc)
    line.gsub(WIKILINK_PATTERN) do |raw_match|
      convert_match(raw_match, Regexp.last_match(1), site, source_doc)
    end
  end

  def convert_match(raw_match, raw_body, site, source_doc)
    target_ref, label = raw_body.split("|", 2).map { |part| part&.strip }
    note_key, section = target_ref.split("#", 2).map { |part| part&.strip }

    return raw_match if note_key.nil? || note_key.empty?

    target_doc = link_index(site)[note_key]
    unless target_doc
      if duplicate_keys(site).key?(note_key)
        warn_once(site, "duplicate:#{note_key}", source_doc,
                  "Multiple Markdown files found for wikilink key '#{note_key}'.")
      else
        warn_once(site, "missing:#{note_key}", source_doc, "No Markdown file found for wikilink key '#{note_key}'.")
      end

      return raw_match
    end

    href = "#{site.config["baseurl"]}#{target_doc.url}"

    if section && !section.empty?
      anchor = section_index(target_doc)[section]
      unless anchor
        warn_once(site, "missing-section:#{note_key}##{section}", source_doc,
                  "No heading '#{section}' found in '#{note_key}'.")
        return raw_match
      end

      href = "#{href}##{anchor}"
    end

    text = label && !label.empty? ? label : target_ref
    "[#{escape_link_text(text)}](#{escape_link_url(href)})"
  end

  def link_index(site)
    cached = site.instance_variable_get(:@obsidian_wikilinks_index)
    return cached if cached

    docs_by_key = Hash.new { |hash, key| hash[key] = [] }

    markdown_docs(site).each do |doc|
      docs_by_key[basename_without_ext(doc)] << doc
    end

    index = {}
    duplicate_keys = {}

    docs_by_key.each do |key, docs|
      if docs.length == 1
        index[key] = docs.first
      else
        duplicate_keys[key] = docs
        paths = docs.map { |doc| relative_path(doc) }.join(", ")
        Jekyll.logger.warn "ObsidianWikilinks:",
                           "Duplicate key '#{key}' found in #{paths}; links to this key will be left unchanged."
      end
    end

    site.instance_variable_set(:@obsidian_wikilinks_duplicate_keys, duplicate_keys)
    site.instance_variable_set(:@obsidian_wikilinks_index, index)
  end

  def duplicate_keys(site)
    site.instance_variable_get(:@obsidian_wikilinks_duplicate_keys) || {}
  end

  def markdown_docs(site)
    collection_docs = site.collections.values.flat_map(&:docs)

    (collection_docs + site.pages).uniq { |doc| doc.path }.select do |doc|
      MARKDOWN_EXTENSIONS.include?(File.extname(doc.path).downcase) && doc.respond_to?(:url) && doc.url
    end
  end

  def section_index(doc)
    cached = doc.instance_variable_get(:@obsidian_wikilinks_section_index)
    return cached if cached

    counts = Hash.new(0)
    headings = {}

    each_non_fenced_line(doc.content) do |line|
      heading_text = extract_heading_text(line)
      next unless heading_text

      base_id = kramdown_header_id(heading_text)
      next if base_id.empty?

      count = counts[base_id]
      counts[base_id] += 1
      generated_id = count.zero? ? base_id : "#{base_id}-#{count}"

      headings[heading_text] ||= generated_id
    end

    doc.instance_variable_set(:@obsidian_wikilinks_section_index, headings)
  end

  def each_non_fenced_line(content)
    in_fence = false
    fence_char = nil
    fence_length = 0

    content.each_line do |line|
      fence = fence_marker(line)

      if fence && !in_fence
        in_fence = true
        fence_char = fence[:char]
        fence_length = fence[:length]
        next
      elsif in_fence
        if fence && fence[:char] == fence_char && fence[:length] >= fence_length
          in_fence = false
          fence_char = nil
          fence_length = 0
        end

        next
      end

      yield line
    end
  end

  def fence_marker(line)
    match = line.match(/\A {0,3}(`{3,}|~{3,})/)
    return nil unless match

    marker = match[1]
    { char: marker[0], length: marker.length }
  end

  def extract_heading_text(line)
    match = line.match(/\A {0,3}\#{1,6}\s+(.+?)\s*\z/)
    return nil unless match

    match[1].sub(/\s+#+\s*\z/, "").strip
  end

  # Mirrors kramdown's default header-id shape closely enough for the headings
  # used in this site, including "2. Docking Tab" -> "docking-tab".
  def kramdown_header_id(text)
    text
      .gsub(/<[^>]+>/, "")
      .gsub(/[`*_~\[\]()]/, "")
      .gsub(/[^\p{L}\p{N} -]+/u, "")
      .sub(/\A[^\p{L}]*/u, "")
      .strip
      .downcase
      .gsub(/[[:space:]]+/, "-")
      .gsub(/-+/, "-")
      .gsub(/\A-+|-+\z/, "")
  end

  def basename_without_ext(doc)
    File.basename(doc.path, File.extname(doc.path))
  end

  def relative_path(doc)
    doc.respond_to?(:relative_path) ? doc.relative_path : doc.path
  end

  def escape_link_text(text)
    text.gsub("]") { "\\]" }
  end

  def escape_link_url(url)
    url.gsub(" ", "%20")
  end

  def warn_once(site, key, source_doc, message)
    warned = site.instance_variable_get(:@obsidian_wikilinks_warnings) || {}
    scoped_key = "#{relative_path(source_doc)}:#{key}"
    return if warned[scoped_key]

    warned[scoped_key] = true
    site.instance_variable_set(:@obsidian_wikilinks_warnings, warned)

    Jekyll.logger.warn "ObsidianWikilinks:", "#{relative_path(source_doc)}: #{message}"
  end
end

Jekyll::Hooks.register [:documents, :pages], :pre_render do |doc|
  next unless ObsidianWikilinks::MARKDOWN_EXTENSIONS.include?(File.extname(doc.path).downcase)

  doc.content = ObsidianWikilinks.convert(doc.content, doc.site, doc)
end
