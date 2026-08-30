# frozen_string_literal: true

require "io/console"
require "json"
require "open3"
require "securerandom"

module OmarchyWhoop
  class Cli
    REDIRECT_URI = CallbackHandler::REDIRECT_URI

    def initialize(
      argv,
      input: $stdin,
      output: $stdout,
      error: $stderr,
      store: SecretStore.new,
      oauth: OAuth.new,
      api: Api.new,
      callback_handler: CallbackHandler.new,
      opener: ->(url) { system("xdg-open", url, out: File::NULL, err: File::NULL) },
      callback_error_notifier: ->(message) {
        system("omarchy-notification-send", "WHOOP setup", message, "-u", "critical", out: File::NULL, err: File::NULL)
      },
      notifier: ->(method) { system("omarchy-shell", "-q", "io.github.jsidoryn.whoop", method, out: File::NULL, err: File::NULL) }
    )
      @argv = argv.dup
      @input = input
      @output = output
      @error = error
      @store = store
      @oauth = oauth
      @api = api
      @callback_handler = callback_handler
      @opener = opener
      @callback_error_notifier = callback_error_notifier
      @notifier = notifier
      @snapshot_connected = false
    end

    def run
      command = @argv.shift || "snapshot"
      case command
      when "snapshot" then snapshot
      when "demo" then emit(Demo.snapshot(@argv.shift || "primed", connected: connected?))
      when "setup" then setup
      when "oauth-callback" then oauth_callback
      when "callback-handler" then callback_handler
      when "status" then status
      when "disconnect" then disconnect
      when "version" then @output.puts OmarchyWhoop::VERSION
      else
        raise ConfigurationError, "Unknown command: #{command}"
      end
      0
    rescue Error, KeyError, JSON::ParserError => error
      if command == "snapshot"
        emit("schemaVersion" => 1, "state" => "error", "mode" => "live", "connected" => @snapshot_connected, "message" => error.message, "fetchedAt" => Time.now.utc.iso8601)
        0
      else
        @error.puts "WHOOP: #{error.message}"
        1
      end
    end

    private

    def snapshot
      scenario = option_value("--demo")
      return emit(Demo.snapshot(scenario || "primed", connected: connected?)) if scenario
      fallback = option_value("--fallback-demo") || "primed"
      bundle = @store.read
      return emit(Demo.snapshot(fallback).merge("message" => "Demo data · Connect WHOOP for your stats")) unless bundle

      @snapshot_connected = true
      emit(Client.new(store: @store, oauth: @oauth, api: @api).snapshot)
    end

    def setup
      ensure_keyring!
      registered = false
      client_id = client_secret = state = nil
      callback = begin
        @callback_handler.capture do
          @output.puts "Registering a temporary per-user WHOOP callback handler…"
          @callback_handler.register!
          registered = true
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
          opened = @opener.call(url)
          @output.puts "\nIf the browser did not open, visit:\n\n  #{url}" if opened == false
          @output.puts <<~TEXT

            Approve access in WHOOP, then allow the browser to open WHOOP for
            Omarchy. You will return to this terminal automatically.
          TEXT
        end
      ensure
        if registered
          begin
            @callback_handler.unregister!
          rescue StandardError => cleanup_error
            @error.puts "WHOOP: temporary callback handler cleanup failed: #{cleanup_error.message}"
            @error.puts "Run `bin/whoop callback-handler remove` after setup completes."
          end
        end
      end
      code = @oauth.callback_code(callback, expected_state: state, redirect_uri: REDIRECT_URI)
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
      client = Client.new(store: @store, oauth: @oauth, api: @api)
      client.store_credentials(bundle)
      begin
        @output.puts "\nConnected. Fetching your first WHOOP snapshot…"
        result = client.snapshot
        @output.puts "Recovery: #{result.dig('recovery', 'score') || 'pending'} · Strain: #{result.dig('cycle', 'strain') || 'pending'} · Sleep: #{result.dig('sleep', 'performance') || 'pending'}"
        @output.puts "\nYou can close this terminal. The bar will update automatically."
      ensure
        notify_shell("setupFinished")
      end
    end

    def oauth_callback
      callback = @argv.shift.to_s
      raise ConfigurationError, "The browser did not provide a WHOOP callback URL." if callback.empty?

      @callback_handler.deliver(callback)
    rescue Error => error
      @callback_error_notifier.call(error.message)
      raise
    end

    def callback_handler
      action = @argv.shift || "status"
      case action
      when "install"
        @callback_handler.register!
        @output.puts "WHOOP callback handler installed for the current user."
      when "remove"
        @callback_handler.unregister!
        @output.puts "WHOOP callback handler removed for the current user."
      when "status"
        emit("registered" => @callback_handler.registered?, "redirectUri" => REDIRECT_URI)
      else
        raise ConfigurationError, "Unknown callback-handler action: #{action}"
      end
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
      value = if @input.respond_to?(:tty?) && @input.tty? && @input.respond_to?(:noecho)
        @input.noecho(&:gets).to_s
      else
        @input.gets.to_s
      end
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

    def connected? = !@store.read.nil?

    def notify_shell(method)
      @notifier.call(method)
    end
  end
end
