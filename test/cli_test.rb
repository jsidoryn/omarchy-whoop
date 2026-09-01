# frozen_string_literal: true

require "stringio"
require_relative "test_helper"

class CliTest < Minitest::Test
  EmptyStore = Struct.new(:unused) do
    def read = nil
  end

  class SetupStore
    attr_reader :bundle
    def available? = true
    def read = @bundle&.dup
    def write(value) = @bundle = value.dup
  end

  class MissingStore
    def available? = true
    def read = nil
    def clear = raise "clear should not be called when credentials are already missing"
  end

  class SetupOAuth
    attr_reader :exchange_args, :authorization_args, :callback_state

    def authorization_url(**args)
      @authorization_args = args
      "https://api.prod.whoop.com/oauth/oauth2/auth?state=#{args.fetch(:state)}"
    end

    def callback_code(callback, expected_state:, redirect_uri:)
      raise "unexpected callback" unless callback == "#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=ready"
      raise "unexpected redirect" unless redirect_uri == OmarchyWhoop::Cli::REDIRECT_URI
      @callback_state = expected_state
      "ready"
    end

    def exchange(**args)
      @exchange_args = args
      {"access_token" => "access-token", "refresh_token" => "refresh-token", "expires_in" => 3600}
    end
  end

  class SetupCallbackHandler
    attr_reader :registered, :delivered, :removed

    def register!
      @registered = true
    end

    def capture(expected_state: nil)
      yield
      "#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=ready"
    end

    def deliver(url)
      @delivered = url
    end

    def registered? = @registered == true

    def unregister!
      @removed = true
      @registered = false
    end
  end

  class FailingCallbackHandler < SetupCallbackHandler
    def deliver(_url)
      raise OmarchyWhoop::ConfigurationError, "No WHOOP setup is waiting for this callback."
    end
  end

  class CaptureFailingCallbackHandler < SetupCallbackHandler
    def capture(expected_state: nil)
      yield
      raise OmarchyWhoop::AuthError, "WHOOP authorization timed out."
    end
  end

  class BusyCallbackHandler < SetupCallbackHandler
    def capture(expected_state: nil)
      raise OmarchyWhoop::ConfigurationError, "Another WHOOP setup is already waiting for browser authorization."
    end
  end

  class CleanupFailingCallbackHandler < SetupCallbackHandler
    def unregister!
      raise Errno::EACCES, "mimeapps.list"
    end
  end

  class SetupApi
    def snapshot(_token)
      {
        cycle: {"id" => 1, "score_state" => "SCORED", "score" => {"strain" => 7.2}},
        recovery: {"score_state" => "SCORED", "score" => {"recovery_score" => 81}},
        sleep: {"score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 90}},
        history: {"records" => []}
      }
    end
  end

  class FailingSetupApi < SetupApi
    def snapshot(_token)
      raise OmarchyWhoop::HttpError.new("WHOOP is temporarily unavailable", status: 503)
    end
  end

  def test_snapshot_preserves_the_requested_fallback_demo
    output = StringIO.new
    status = OmarchyWhoop::Cli.new(
      %w[snapshot --fallback-demo strained],
      output: output,
      error: StringIO.new,
      store: EmptyStore.new
    ).run

    result = JSON.parse(output.string)
    assert_equal 0, status
    assert_equal "demo", result.fetch("mode")
    assert_equal "strained", result.fetch("demoScenario")
    assert_match(/Connect WHOOP/, result.fetch("message"))
  end

  def test_snapshot_defaults_to_the_primed_demo_without_credentials
    output = StringIO.new
    OmarchyWhoop::Cli.new(
      ["snapshot"],
      output: output,
      error: StringIO.new,
      store: EmptyStore.new
    ).run

    assert_equal "primed", JSON.parse(output.string).fetch("demoScenario")
  end

  def test_snapshot_reports_live_failures_as_a_connected_error_snapshot
    Dir.mktmpdir do |directory|
      previous_runtime_directory = ENV["XDG_RUNTIME_DIR"]
      ENV["XDG_RUNTIME_DIR"] = directory
      store = SetupStore.new
      store.write("client_id" => "id-123", "client_secret" => "secret-456", "access_token" => "access-789", "refresh_token" => "refresh-012", "expires_at" => Time.now.to_i + 3600)
      output = StringIO.new

      status = OmarchyWhoop::Cli.new(["snapshot"], output: output, error: StringIO.new, store: store, api: FailingSetupApi.new).run

      result = JSON.parse(output.string)
      assert_equal 0, status
      assert_equal "error", result.fetch("state")
      assert_equal "live", result.fetch("mode")
      assert_equal true, result.fetch("connected")
      assert_match(/temporarily unavailable/i, result.fetch("message"))
      refute output.string.match?(/id-123|secret-456|access-789|refresh-012/)
    ensure
      ENV["XDG_RUNTIME_DIR"] = previous_runtime_directory
    end
  end

  def test_status_reports_connection_without_revealing_credentials
    store = SetupStore.new
    store.write("client_id" => "id-123", "client_secret" => "secret-456", "access_token" => "access-789", "refresh_token" => "refresh-012", "expires_at" => 1_700_000_000, "scope" => "offline read:recovery")
    output = StringIO.new

    status = OmarchyWhoop::Cli.new(["status"], output: output, error: StringIO.new, store: store).run

    result = JSON.parse(output.string)
    assert_equal 0, status
    assert_equal true, result.fetch("connected")
    assert_equal 1_700_000_000, result.fetch("expiresAt")
    assert_equal %w[offline read:recovery], result.fetch("scopes")
    refute output.string.match?(/id-123|secret-456|access-789|refresh-012/)
  end

  def test_disconnect_is_successful_when_already_disconnected
    output = StringIO.new
    error = StringIO.new
    notified = []

    status = OmarchyWhoop::Cli.new(
      ["disconnect"],
      output: output,
      error: error,
      store: MissingStore.new,
      notifier: ->(method) { notified << method }
    ).run

    assert_equal 0, status
    assert_equal "", error.string
    assert_equal ["setupFinished"], notified
    assert_match(/already disconnected/i, output.string)
    assert_match(/no credentials were found/i, output.string)
  end

  def test_setup_guides_oauth_without_printing_credentials
    input = StringIO.new("\nclient-id\nclient-secret\n")
    output = StringIO.new
    store = SetupStore.new
    oauth = SetupOAuth.new
    callback_handler = SetupCallbackHandler.new
    opened = []
    notified = []

    status = OmarchyWhoop::Cli.new(
      ["setup"],
      input: input,
      output: output,
      error: StringIO.new,
      store: store,
      oauth: oauth,
      api: SetupApi.new,
      callback_handler: callback_handler,
      opener: ->(url) { opened << url },
      notifier: ->(method) { notified << method }
    ).run

    assert_equal 0, status
    assert_equal OmarchyWhoop::Cli::REDIRECT_URI, oauth.authorization_args.fetch(:redirect_uri)
    assert_equal 32, oauth.authorization_args.fetch(:state).length
    assert_equal oauth.authorization_args.fetch(:state), oauth.callback_state
    assert_equal oauth.authorization_args.fetch(:code_verifier), oauth.exchange_args.fetch(:code_verifier)
    assert_equal "client-id", store.bundle.fetch("client_id")
    assert_equal "client-secret", store.bundle.fetch("client_secret")
    assert_equal "refresh-token", store.bundle.fetch("refresh_token")
    assert_equal 1, opened.length
    assert_equal ["setupFinished"], notified
    refute callback_handler.registered
    assert callback_handler.removed
    assert_match(/Enable these scopes/, output.string)
    assert_match(/#{Regexp.escape(OmarchyWhoop::CallbackHandler::REDIRECT_URI)}/, output.string)
    assert_match(/return to this terminal automatically/i, output.string)
    refute output.string.include?("client-secret")
    refute output.string.include?("refresh-token")
  end

  def test_setup_notifies_the_shell_even_when_the_first_fetch_fails
    input = StringIO.new("\nclient-id\nclient-secret\n")
    output = StringIO.new
    error = StringIO.new
    store = SetupStore.new
    notified = []

    callback_handler = SetupCallbackHandler.new
    status = OmarchyWhoop::Cli.new(
      ["setup"],
      input: input,
      output: output,
      error: error,
      store: store,
      oauth: SetupOAuth.new,
      api: FailingSetupApi.new,
      callback_handler: callback_handler,
      opener: ->(_url) { true },
      notifier: ->(method) { notified << method }
    ).run

    assert_equal 1, status
    assert callback_handler.removed
    assert_equal ["setupFinished"], notified
    assert_equal "refresh-token", store.bundle.fetch("refresh_token")
    assert_match(/temporarily unavailable/i, error.string)
  end

  def test_setup_removes_the_temporary_handler_when_authorization_fails
    input = StringIO.new("\nclient-id\nclient-secret\n")
    error = StringIO.new
    callback_handler = CaptureFailingCallbackHandler.new

    status = OmarchyWhoop::Cli.new(
      ["setup"],
      input: input,
      output: StringIO.new,
      error: error,
      store: SetupStore.new,
      oauth: SetupOAuth.new,
      callback_handler: callback_handler,
      opener: ->(_url) { true }
    ).run

    assert_equal 1, status
    refute callback_handler.registered
    assert callback_handler.removed
    assert_match(/authorization timed out/i, error.string)
  end

  def test_setup_does_not_touch_the_handler_when_another_setup_owns_the_lock
    callback_handler = BusyCallbackHandler.new
    error = StringIO.new

    status = OmarchyWhoop::Cli.new(
      ["setup"],
      input: StringIO.new,
      output: StringIO.new,
      error: error,
      store: SetupStore.new,
      oauth: SetupOAuth.new,
      callback_handler: callback_handler
    ).run

    assert_equal 1, status
    refute callback_handler.registered
    refute callback_handler.removed
    assert_match(/Another WHOOP setup/, error.string)
  end

  def test_setup_preserves_success_when_temporary_handler_cleanup_fails
    callback_handler = CleanupFailingCallbackHandler.new
    store = SetupStore.new
    error = StringIO.new

    status = OmarchyWhoop::Cli.new(
      ["setup"],
      input: StringIO.new("\nclient-id\nclient-secret\n"),
      output: StringIO.new,
      error: error,
      store: store,
      oauth: SetupOAuth.new,
      api: SetupApi.new,
      callback_handler: callback_handler,
      opener: ->(_url) { true }
    ).run

    assert_equal 0, status
    assert_equal "refresh-token", store.bundle.fetch("refresh_token")
    assert_match(/cleanup failed/i, error.string)
    assert_match(/callback-handler remove/, error.string)
  end

  def test_oauth_callback_forwards_the_url_to_the_waiting_setup
    callback_handler = SetupCallbackHandler.new
    callback = "#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=ready&state=Ab12Cd34"

    status = OmarchyWhoop::Cli.new(
      ["oauth-callback", callback],
      output: StringIO.new,
      error: StringIO.new,
      callback_handler: callback_handler
    ).run

    assert_equal 0, status
    assert_equal callback, callback_handler.delivered
  end

  def test_oauth_callback_notifies_when_browser_delivery_fails
    notifications = []
    callback = "#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=ready&state=Ab12Cd34"

    status = OmarchyWhoop::Cli.new(
      ["oauth-callback", callback],
      output: StringIO.new,
      error: StringIO.new,
      callback_handler: FailingCallbackHandler.new,
      callback_error_notifier: ->(message) { notifications << message }
    ).run

    assert_equal 1, status
    assert_equal ["No WHOOP setup is waiting for this callback."], notifications
    refute notifications.join.include?(callback)
  end

  def test_callback_handler_can_be_inspected_and_removed
    callback_handler = SetupCallbackHandler.new
    callback_handler.register!
    output = StringIO.new

    status = OmarchyWhoop::Cli.new(
      ["callback-handler", "status"],
      output: output,
      error: StringIO.new,
      callback_handler: callback_handler
    ).run
    removal_status = OmarchyWhoop::Cli.new(
      ["callback-handler", "remove"],
      output: StringIO.new,
      error: StringIO.new,
      callback_handler: callback_handler
    ).run

    assert_equal 0, status
    assert_equal true, JSON.parse(output.string).fetch("registered")
    assert_equal 0, removal_status
    assert callback_handler.removed
  end
end
