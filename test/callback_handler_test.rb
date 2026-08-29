# frozen_string_literal: true

require "stringio"
require "thread"
require_relative "test_helper"

class CallbackHandlerTest < Minitest::Test
  Result = Struct.new(:stdout, :stderr, :success?)

  class DesktopRunner
    attr_reader :calls

    def initialize(current: "")
      @current = current
      @calls = []
    end

    def call(argv)
      @calls << argv
      case argv
      when ["xdg-mime", "query", "default", OmarchyWhoop::CallbackHandler::MIME_TYPE]
        Result.new("#{@current}\n", "", true)
      when ["xdg-mime", "default", OmarchyWhoop::CallbackHandler::DESKTOP_ID, OmarchyWhoop::CallbackHandler::MIME_TYPE]
        @current = OmarchyWhoop::CallbackHandler::DESKTOP_ID
        Result.new("", "", true)
      else
        Result.new("", "", true)
      end
    end
  end

  class FailingDesktopRunner < DesktopRunner
    def call(argv)
      return Result.new("", "registration failed", false) if argv[0, 2] == ["xdg-mime", "default"]

      super
    end
  end

  def test_registers_a_per_user_desktop_handler_without_credentials
    Dir.mktmpdir do |directory|
      runner = DesktopRunner.new
      handler = build_handler(directory, runner: runner)

      assert handler.register!

      entry = File.read(handler.desktop_file)
      assert entry.include?("Name=WHOOP for Omarchy")
      assert entry.include?("Exec=\"/plugin/bin/whoop\" oauth-callback %u")
      assert entry.include?("MimeType=#{OmarchyWhoop::CallbackHandler::MIME_TYPE};")
      refute entry.match?(/client.secret|access.token|refresh.token/i)
      assert runner.calls.include?([
        "xdg-mime", "default", OmarchyWhoop::CallbackHandler::DESKTOP_ID,
        OmarchyWhoop::CallbackHandler::MIME_TYPE
      ])
    end
  end

  def test_refuses_to_replace_an_existing_scheme_handler
    Dir.mktmpdir do |directory|
      runner = DesktopRunner.new(current: "some-other-app.desktop")
      handler = build_handler(directory, runner: runner)

      error = assert_raises(OmarchyWhoop::ConfigurationError) { handler.register! }

      assert_match(/some-other-app\.desktop/, error.message)
      refute File.exist?(handler.desktop_file)
    end
  end

  def test_delivers_the_callback_to_the_waiting_setup_without_persisting_it
    Dir.mktmpdir do |directory|
      handler = build_handler(directory, runner: DesktopRunner.new, wait_seconds: 2)
      ready = Queue.new
      callback = "#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=ready&state=Ab12Cd34"
      received = nil

      listener = Thread.new do
        received = handler.capture do
          ready << true
        end
      end
      ready.pop
      handler.deliver(callback)
      listener.join

      assert_equal callback, received
      refute File.exist?(handler.socket_path)
      assert_equal 0, File.size(handler.lock_path)
      refute File.binread(handler.lock_path).include?("ready")
    end
  end

  def test_rejects_delivery_when_no_setup_is_waiting
    Dir.mktmpdir do |directory|
      handler = build_handler(directory, runner: DesktopRunner.new)

      error = assert_raises(OmarchyWhoop::ConfigurationError) do
        handler.deliver("#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=late")
      end

      assert_match(/No WHOOP setup is waiting/, error.message)
    end
  end

  def test_rejects_an_empty_connection_without_a_ruby_exception
    Dir.mktmpdir do |directory|
      handler = build_handler(directory, runner: DesktopRunner.new, wait_seconds: 1)
      ready = Queue.new
      error = nil

      listener = Thread.new do
        handler.capture { ready << true }
      rescue StandardError => caught
        error = caught
      end
      ready.pop
      UNIXSocket.open(handler.socket_path, &:close)
      listener.join

      assert_equal OmarchyWhoop::AuthError, error.class
      assert_match(/callback was empty/i, error.message)
    end
  end

  def test_times_out_a_connected_peer_that_never_finishes_writing
    Dir.mktmpdir do |directory|
      handler = build_handler(directory, runner: DesktopRunner.new, wait_seconds: 0.05)
      ready = Queue.new
      error = nil

      listener = Thread.new do
        handler.capture { ready << true }
      rescue StandardError => caught
        error = caught
      end
      ready.pop
      socket = UNIXSocket.open(handler.socket_path)
      socket.write("#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=incomplete")
      listener.join

      assert_equal OmarchyWhoop::AuthError, error.class
      assert_match(/timed out/i, error.message)
    ensure
      socket&.close
    end
  end

  def test_rejects_an_oversized_callback
    Dir.mktmpdir do |directory|
      handler = build_handler(directory, runner: DesktopRunner.new, wait_seconds: 1)
      ready = Queue.new
      error = nil

      listener = Thread.new do
        handler.capture { ready << true }
      rescue StandardError => caught
        error = caught
      end
      ready.pop
      socket = UNIXSocket.open(handler.socket_path)
      socket.write("#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=#{'x' * OmarchyWhoop::CallbackHandler::MAX_CALLBACK_BYTES}")
      socket.close
      listener.join

      assert_equal OmarchyWhoop::AuthError, error.class
      assert_match(/unexpectedly large/i, error.message)
    end
  end

  def test_refuses_a_second_concurrent_setup
    Dir.mktmpdir do |directory|
      first = build_handler(directory, runner: DesktopRunner.new, wait_seconds: 2)
      second = build_handler(directory, runner: DesktopRunner.new, wait_seconds: 2)
      ready = Queue.new
      callback = "#{OmarchyWhoop::CallbackHandler::REDIRECT_URI}?code=ready&state=Ab12Cd34"

      listener = Thread.new { first.capture { ready << true } }
      ready.pop
      error = assert_raises(OmarchyWhoop::ConfigurationError) { second.capture {} }
      first.deliver(callback)
      listener.join

      assert_match(/Another WHOOP setup/, error.message)
    end
  end

  def test_failed_registration_removes_the_partial_desktop_entry
    Dir.mktmpdir do |directory|
      handler = build_handler(directory, runner: FailingDesktopRunner.new)

      assert_raises(OmarchyWhoop::ConfigurationError) { handler.register! }

      refute File.exist?(handler.desktop_file)
    end
  end

  def test_unregister_removes_only_its_desktop_entry_and_associations
    Dir.mktmpdir do |directory|
      runner = DesktopRunner.new
      handler = build_handler(directory, runner: runner)
      handler.register!
      mimeapps = File.join(directory, "config", "mimeapps.list")
      FileUtils.mkdir_p(File.dirname(mimeapps))
      File.write(mimeapps, <<~MIMEAPPS)
        [Default Applications]
        #{OmarchyWhoop::CallbackHandler::MIME_TYPE}=#{OmarchyWhoop::CallbackHandler::DESKTOP_ID};other.desktop;
        text/plain=editor.desktop;

        [Added Associations]
        #{OmarchyWhoop::CallbackHandler::MIME_TYPE}=#{OmarchyWhoop::CallbackHandler::DESKTOP_ID};
      MIMEAPPS

      assert handler.unregister!

      refute File.exist?(handler.desktop_file)
      content = File.read(mimeapps)
      assert content.include?("#{OmarchyWhoop::CallbackHandler::MIME_TYPE}=other.desktop;")
      assert content.include?("text/plain=editor.desktop;")
      refute content.include?(OmarchyWhoop::CallbackHandler::DESKTOP_ID)
    end
  end

  private

  def build_handler(directory, runner:, wait_seconds: 1)
    OmarchyWhoop::CallbackHandler.new(
      helper_path: "/plugin/bin/whoop",
      data_home: File.join(directory, "data"),
      config_home: File.join(directory, "config"),
      runtime_dir: File.join(directory, "runtime"),
      runner: runner,
      wait_seconds: wait_seconds
    )
  end
end
