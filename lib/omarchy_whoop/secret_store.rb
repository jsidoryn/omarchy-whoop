# frozen_string_literal: true

require "json"
require "open3"

module OmarchyWhoop
  class SecretStore
    SERVICE = "omarchy-whoop"
    ACCOUNT = "credentials"
    LABEL = "Omarchy WHOOP credentials"

    Result = Struct.new(:stdout, :stderr, :success?)

    def initialize(runner: nil)
      @runner = runner || method(:run)
    end

    def available?
      _stdout, _stderr, status = Open3.capture3("bash", "-lc", "command -v secret-tool")
      status.success?
    end

    def read
      result = @runner.call(["secret-tool", "lookup", "service", SERVICE, "account", ACCOUNT], stdin_data: nil)
      return nil unless result.success?
      text = result.stdout.to_s.strip
      return nil if text.empty?

      JSON.parse(text)
    rescue JSON::ParserError
      raise ConfigurationError, "The WHOOP keyring entry is not valid JSON. Disconnect and reconnect WHOOP."
    end

    # The entire credential set is one item. WHOOP rotates both access and
    # refresh tokens, so replacing one JSON value avoids a half-updated pair.
    def write(bundle)
      payload = JSON.generate(bundle)
      result = @runner.call(
        ["secret-tool", "store", "--label=#{LABEL}", "service", SERVICE, "account", ACCOUNT],
        stdin_data: payload
      )
      return true if result.success?

      raise ConfigurationError, concise(result.stderr, "Could not save credentials in the system keyring")
    end

    def clear
      result = @runner.call(["secret-tool", "clear", "service", SERVICE, "account", ACCOUNT], stdin_data: nil)
      result.success?
    end

    private

    def run(argv, stdin_data: nil)
      stdout, stderr, status = Open3.capture3(*argv, stdin_data: stdin_data.to_s)
      Result.new(stdout, stderr, status.success?)
    end

    def concise(value, fallback)
      line = value.to_s.lines.map(&:strip).find { |item| !item.empty? }
      line.nil? ? fallback : "#{fallback}: #{line[0, 180]}"
    end
  end
end

