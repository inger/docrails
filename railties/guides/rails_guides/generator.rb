require 'set'

class String
  def html_safe!
    self
  end unless "post 9415935902f120a9bac0bfce7129725a0db38ed3".respond_to?(:html_safe!)
end

module RailsGuides
  class Generator
    attr_reader :output, :view_path, :view, :guides_dir

    def initialize(output = nil)
      @guides_dir = File.join(File.dirname(__FILE__), '..')

      @output = output || File.join(@guides_dir, "output")

      unless ENV["ONLY"]
        FileUtils.rm_r(@output) if File.directory?(@output)
        FileUtils.mkdir(@output)
      end

      @view_path = File.join(@guides_dir, "source")
    end

    def generate
      guides = Dir.entries(view_path).find_all {|g| g =~ /\.textile(?:\.erb)?$/ }

      if ENV["ONLY"]
        only = ENV["ONLY"].split(",").map{|x| x.strip }.map {|o| "#{o}.textile" }
        guides = guides.find_all {|g| only.include?(g) }
        puts "GENERATING ONLY #{guides.inspect}"
      end

      guides.each do |guide|
        generate_guide(guide)
      end

      # Copy images and css files to html directory
      FileUtils.cp_r File.join(guides_dir, 'images'), File.join(output, 'images')
      FileUtils.cp_r File.join(guides_dir, 'files'), File.join(output, 'files')
    end

    def generate_guide(guide)
      guide =~ /(.*?)\.textile(?:\.erb)?$/
      name = $1

      puts "Generating #{name}"

      file = File.join(output, "#{name}.html")
      File.open(file, 'w') do |f|
        @view = ActionView::Base.new(view_path)
        @view.extend(Helpers)

        if guide =~ /\.textile\.erb$/
          # Generate the erb pages with textile formatting - e.g. index/authors
          result = view.render(:layout => 'layout', :file => guide)
          f.write textile(result)
        else
          body = File.read(File.join(view_path, guide))
          body = set_header_section(body, @view)
          body = set_index(body, @view)

          result = view.render(:layout => 'layout', :text => textile(body).html_safe!)
          f.write result
          warn_about_broken_links(result) if ENV.key?("WARN_BROKEN_LINKS")
        end
      end
    end

    def set_header_section(body, view)
      new_body = body.gsub(/(.*?)endprologue\./m, '').strip
      header = $1

      header =~ /h2\.(.*)/
      page_title = $1.strip

      header = textile(header)

      view.content_for(:page_title) { page_title.html_safe! }
      view.content_for(:header_section) { header.html_safe! }
      new_body
    end

    def set_index(body, view)
      index = <<-INDEX
      <div id="subCol">
        <h3 class="chapter"><img src="images/chapters_icon.gif" alt="" />Chapters</h3>
        <ol class="chapters">
      INDEX

      i = Indexer.new(body)
      i.index

      # Set index for 2 levels
      i.level_hash.each do |key, value|
        link = view.content_tag(:a, :href => key[:id]) { textile(key[:title]) }

        children = value.keys.map do |k|
          l = view.content_tag(:a, :href => k[:id]) { textile(k[:title]) }
          view.content_tag(:li, l)
        end

        children_ul = view.content_tag(:ul, children)

        index << view.content_tag(:li, link + children_ul)
      end

      index << '</ol>'
      index << '</div>'

      view.content_for(:index_section) { index.html_safe! }

      i.result
    end

    def textile(body)
      # If the issue with notextile is fixed just remove the wrapper.
      with_workaround_for_notextile(body) do |body|
        t = RedCloth.new(body)
        t.hard_breaks = false
        t.to_html(:notestuff, :plusplus, :code, :tip)
      end
    end

    # For some reason the notextile tag does not always turn off textile. See
    # LH ticket of the security guide (#7). As a temporary workaround we deal
    # with code blocks by hand.
    def with_workaround_for_notextile(body)
      code_blocks = []
      body.gsub!(%r{<(yaml|shell|ruby|erb|html|sql|plain)>(.*?)</\1>}m) do |m|
        es = ERB::Util.h($2)
        css_class = ['erb', 'shell'].include?($1) ? 'html' : $1
        code_blocks << %{<div class="code_container"><code class="#{css_class}">#{es}</code></div>}
        "\ndirty_workaround_for_notextile_#{code_blocks.size - 1}\n"
      end
      
      body = yield body
      
      body.gsub(%r{<p>dirty_workaround_for_notextile_(\d+)</p>}) do |_|
        code_blocks[$1.to_i]
      end
    end

    def warn_about_broken_links(html)
      anchors = extract_anchors(html)
      check_fragment_identifiers(html, anchors)
    end
    
    def extract_anchors(html)
      # Textile generates headers with IDs computed from titles.
      anchors = Set.new
      html.scan(/<h\d\s+id="([^"]+)/).flatten.each do |anchor|
        if anchors.member?(anchor)
          puts "*** DUPLICATE HEADER ID: #{anchor}, please consider rewording" if ENV.key?("WARN_DUPLICATE_HEADERS")
        else
          anchors << anchor
        end
      end

      # Also, footnotes are rendered as paragraphs this way.
      anchors += Set.new(html.scan(/<p\s+class="footnote"\s+id="([^"]+)/).flatten)
      return anchors
    end
    
    def check_fragment_identifiers(html, anchors)
      html.scan(/<a\s+href="#([^"]+)/).flatten.each do |fragment_identifier|
        next if fragment_identifier == 'mainCol' # in layout, jumps to some DIV
        unless anchors.member?(fragment_identifier)
          guess = anchors.min { |a, b|
            Levenshtein.distance(fragment_identifier, a) <=> Levenshtein.distance(fragment_identifier, b)
          }
          puts "*** BROKEN LINK: ##{fragment_identifier}, perhaps you meant ##{guess}."
        end
      end
    end
  end
end
