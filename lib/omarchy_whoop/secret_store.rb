# frozen_string_literal: true

require "json"
require "open3"
require "timeout"

module OmarchyWhoop
  class SecretStore
    SERVICE = "omarchy-whoop"
    ACCOUNT = "credentials"
    LABEL = "Omarchy WHOOP credentials"

    def initialize(runner: nil)
      @runner = runner || method(:run)
    end

    def available?
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        path = File.join(directory, "secret-tool")
        File.file?(path) && File.executable?(path)
      end
    end

    def read
      result = execute(["secret-tool", "lookup", "service", SERVICE, "account", ACCOUNT], stdin_data: nil)
      unless result.success?
        return nil if result.stderr.to_s.strip.empty?
        raise ConfigurationError, concise(result.stderr, "Could not read credentials from the system keyring")
      end
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
      result = execute(
        ["secret-tool", "store", "--label=#{LABEL}", "service", SERVICE, "account", ACCOUNT],
        stdin_data: payload
      )
      return true if result.success?

      raise ConfigurationError, concise(result.stderr, "Could not save credentials in the system keyring")
    end

    def clear
      result = execute(["secret-tool", "clear", "service", SERVICE, "account", ACCOUNT], stdin_data: nil)
      return true if result.success?

      raise ConfigurationError, concise(result.stderr, "Could not remove credentials from the system keyring")
    end

    private

    def run(argv, stdin_data: nil)
      stdout, stderr, status = Timeout.timeout(30) do
        Open3.capture3(*argv, stdin_data: stdin_data.to_s)
      end
      Subprocess::Result.new(stdout, stderr, status.success?)
    rescue Timeout::Error
      raise ConfigurationError, "secret-tool timed out. Unlock your keyring and try again."
    end

    def execute(argv, stdin_data: nil)
      @runner.call(argv, stdin_data: stdin_data)
    rescue SystemCallError => error
      raise ConfigurationError, "secret-tool could not run: #{error.message}"
    end

    def concise(value, fallback) = Subprocess.concise(value, fallback)
  end
end
