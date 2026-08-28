# frozen_string_literal: true

require "io/console"
require "json"
require "open3"
require "securerandom"
require "shellwords"

module OmarchyWhoop
  class Cli
    REDIRECT_URI = "whoop://omarchy/callback"

    def initialize(
      argv,
      input: $stdin,
      output: $stdout,
      error: $stderr,
      store: SecretStore.new,
      oauth: OAuth.new,
      api: Api.new,
      opener: ->(url) { system("xdg-open", url, out: File::NULL, err: File::NULL) },
      notifier: ->(method) { system("omarchy-shell", "-q", "io.github.jsidoryn.whoop", method, out: File::NULL, err: File::NULL) }
    )
      @argv = argv.dup
      @input = input
      @output = output
      @error = error
      @store = store
      @oauth = oauth
      @api = api
      @opener = opener
      @notifier = notifier
    end

    def run
      command = @argv.shift || "snapshot"
      case command
      when "snapshot" then snapshot
      when "demo" then emit(Demo.snapshot(@argv.shift || "primed"))
      when "setup" then setup
      when "status" then status
      when "disconnect" then disconnect
      when "version" then @output.puts OmarchyWhoop::VERSION
      else
        raise ConfigurationError, "Unknown command: #{command}"
      end
      0
    rescue Error, KeyError, JSON::ParserError => error
      if command == "snapshot"
        emit("schemaVersion" => 1, "state" => "error", "mode" => "live", "message" => error.message, "fetchedAt" => Time.now.utc.iso8601)
        0
      else
        @error.puts "WHOOP: #{error.message}"
        1
      end
    end

    private

    def snapshot
      scenario = option_value("--demo")
      return emit(Demo.snapshot(scenario || "primed")) if scenario
      fallback = option_value("--fallback-demo") || "primed"
      return emit(Demo.snapshot(fallback).merge("message" => "Demo data · Connect WHOOP for your stats")) unless @store.read

      emit(Client.new(store: @store, oauth: @oauth, api: @api).snapshot)
    end

    def setup
      ensure_keyring!
      heading("Connect WHOOP to Omarchy")
      @output.puts <<~TEXT
        Before continuing, create an app in the WHOOP Developer Dashboard:

          https://developer-dashboard.whoop.com/

        Use this exact redirect URL:

          #{REDIRECT_URI}

        Enable these scopes:

          #{OAuth::SCOPES.join("  ")}

        This plugin stores one credential bundle in your system keyring. It never
        writes credentials to shell.json, the plugin folder, or its data cache.
      TEXT
      prompt("Press Enter when your WHOOP app is ready")
      client_id = prompt("Client ID: ").strip
      raise ConfigurationError, "Client ID cannot be empty." if client_id.empty?
      client_secret = secret_prompt("Client Secret: ").strip
      raise ConfigurationError, "Client Secret cannot be empty." if client_secret.empty?

      state = SecureRandom.alphanumeric(8)
      url = @oauth.authorization_url(client_id:, redirect_uri: REDIRECT_URI, state:)
      @output.puts "\nOpening WHOOP authorization in your browser…"
      @opener.call(url)
      @output.puts <<~TEXT

        Approve access in WHOOP. Your browser may say it cannot open the final
        whoop:// address; that is expected. Copy the complete final address from
        the browser's address bar and paste it below.
      TEXT
      callback = prompt("WHOOP callback URL: ").strip
      code = @oauth.callback_code(callback, expected_state: state)
      tokens = @oauth.exchange(client_id:, client_secret:, redirect_uri: REDIRECT_URI, code:)
      bundle = {
        "client_id" => client_id,
        "client_secret" => client_secret,
        "redirect_uri" => REDIRECT_URI,
        "access_token" => tokens.fetch("access_token"),
        "refresh_token" => tokens.fetch("refresh_token"),
        "expires_at" => Time.now.to_i + tokens.fetch("expires_in").to_i,
        "scope" => tokens["scope"] || OAuth::SCOPES.join(" ")
      }
      @store.write(bundle)
      @output.puts "\nConnected. Fetching your first WHOOP snapshot…"
      result = Client.new(store: @store, oauth: @oauth, api: @api).snapshot
      @output.puts "Recovery: #{result.dig('recovery', 'score') || 'pending'} · Strain: #{result.dig('cycle', 'strain') || 'pending'} · Sleep: #{result.dig('sleep', 'performance') || 'pending'}"
      notify_shell("setupFinished")
      @output.puts "\nYou can close this terminal. The bar will update automatically."
    end

    def status
      bundle = @store.read
      emit(
        "connected" => !bundle.nil?,
        "storage" => "secret-tool",
        "expiresAt" => bundle && bundle["expires_at"],
        "scopes" => bundle ? bundle["scope"].to_s.split : []
      )
    end

    def disconnect
      Client.new(store: @store, oauth: @oauth, api: @api).disconnect
      notify_shell("setupFinished")
      @output.puts "WHOOP credentials were removed from the system keyring."
    end

    def ensure_keyring!
      raise ConfigurationError, "secret-tool was not found. Install libsecret first." unless @store.available?
    end

    def prompt(text)
      @output.print text
      @output.flush
      @input.gets.to_s
    end

    def secret_prompt(text)
      @output.print text
      @output.flush
      value = if @input.respond_to?(:noecho) then @input.noecho(&:gets).to_s else @input.gets.to_s end
      @output.puts
      value
    end

    def heading(text)
      @output.puts "\n#{text}\n#{"=" * text.length}\n"
    end

    def option_value(name)
      index = @argv.index(name)
      return nil unless index
      @argv[index + 1] || "primed"
    end

    def emit(value) = @output.puts(JSON.generate(value))

    def notify_shell(method)
      @notifier.call(method)
    end
  end
end
