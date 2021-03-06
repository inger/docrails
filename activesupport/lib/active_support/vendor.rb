def ActiveSupport.requirable?(file)
  $LOAD_PATH.any? { |p| Dir.glob("#{p}/#{file}.*").any? }
end

[%w(builder 2.1.2), %w(i18n 0.1.3), %w(memcache-client 1.7.5), %w(tzinfo 0.3.13)].each do |lib, version|
  # If the lib is not already requirable
  unless ActiveSupport.requirable? lib
    # Try to activate a gem ~> satisfying the requested version first.
    begin
      gem lib, "~> #{version}"
      # Use the vendored lib if the gem's missing or we aren't using RubyGems.
    rescue LoadError, NoMethodError
      $LOAD_PATH.unshift File.expand_path("#{File.dirname(__FILE__)}/vendor/#{lib}-#{version}/lib")
    end
  end
end
