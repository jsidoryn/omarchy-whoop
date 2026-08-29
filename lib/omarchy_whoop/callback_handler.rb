# frozen_string_literal: true

require "fileutils"
require "open3"
require "socket"
require "uri"

module OmarchyWhoop
  class CallbackHandler
    SCHEME = "io.github.jsidoryn.omarchy-whoop"
    REDIRECT_URI = "#{SCHEME}://oauth/callback"
    MIME_TYPE = "x-scheme-handler/#{SCHEME}"
    DESKTOP_ID = "io.github.jsidoryn.omarchy-whoop-oauth.desktop"
    MAX_CALLBACK_BYTES = 8_192
    DEFAULT_WAIT_SECONDS = 300

    Result = Struct.new(:stdout, :stderr, :success?)

    attr_reader :desktop_file, :socket_path, :lock_path

    def initialize(
      helper_path: File.expand_path("../../bin/whoop", __dir__),
      data_home: default_data_home,
      config_home: default_config_home,
      runtime_dir: ENV["XDG_RUNTIME_DIR"],
      runner: nil,
      wait_seconds: DEFAULT_WAIT_SECONDS
    )
      @helper_path = File.expand_path(helper_path)
      @applications_dir = File.join(data_home, "applications")
      @desktop_file = File.join(@applications_dir, DESKTOP_ID)
      @config_home = config_home
      @socket_path = runtime_dir && File.join(runtime_dir, "omarchy-whoop", "oauth-callback.sock")
      @lock_path = runtime_dir && File.join(runtime_dir, "omarchy-whoop", "oauth-callback.lock")
      @runner = runner || method(:run)
      @wait_seconds = wait_seconds
    end

    def register!
      current = current_handler
      if !current.empty? && current != DESKTOP_ID
        raise ConfigurationError, "#{SCHEME} is already handled by #{current}; WHOOP setup will not replace it."
      end

      previous_entry = File.binread(@desktop_file) if File.file?(@desktop_file)
      begin
        FileUtils.mkdir_p(@applications_dir)
        atomic_write(@desktop_file, desktop_entry, mode: 0o644)
        run_optional(["update-desktop-database", @applications_dir])
        execute!(["xdg-mime", "default", DESKTOP_ID, MIME_TYPE], "Could not register the WHOOP callback handler")

        actual = current_handler
        return true if actual == DESKTOP_ID

        raise ConfigurationError, "The desktop did not activate the WHOOP callback handler."
      rescue StandardError
        if previous_entry
          atomic_write(@desktop_file, previous_entry, mode: 0o644)
        else
          File.unlink(@desktop_file) if File.file?(@desktop_file)
          remove_user_associations
        end
        raise
      end
    end

    def unregister!
      if File.file?(@desktop_file)
        content = File.binread(@desktop_file)
        unless content.include?("Name=WHOOP for Omarchy") && content.include?("MimeType=#{MIME_TYPE};")
          raise ConfigurationError, "The callback desktop entry is not owned by WHOOP for Omarchy."
        end
        File.unlink(@desktop_file)
      end

      remove_user_associations
      run_optional(["update-desktop-database", @applications_dir])
      true
    end

    def registered?
      current_handler == DESKTOP_ID && File.file?(@desktop_file)
    end

    def capture
      lock = acquire_lock
      server = open_server
      yield
      deadline = monotonic_time + @wait_seconds
      wait_until_readable(server, deadline)
      connection = server.accept
      validate_callback(read_callback(connection, deadline))
    ensure
      connection&.close
      server&.close
      remove_owned_socket if lock
      lock&.flock(File::LOCK_UN)
      lock&.close
    end

    def deliver(callback)
      callback = validate_callback(callback)
      raise ConfigurationError, "No WHOOP setup is waiting for this callback." unless @socket_path && File.socket?(@socket_path)

      UNIXSocket.open(@socket_path) { |socket| socket.write(callback) }
      true
    rescue Errno::ENOENT, Errno::ECONNREFUSED
      raise ConfigurationError, "No WHOOP setup is waiting for this callback."
    rescue SystemCallError
      raise ConfigurationError, "The browser could not deliver the WHOOP callback to the waiting setup."
    end

    private

    def default_data_home
      ENV["XDG_DATA_HOME"].to_s.empty? ? File.join(Dir.home, ".local", "share") : ENV.fetch("XDG_DATA_HOME")
    end

    def default_config_home
      ENV["XDG_CONFIG_HOME"].to_s.empty? ? File.join(Dir.home, ".config") : ENV.fetch("XDG_CONFIG_HOME")
    end

    def current_handler
      result = execute(["xdg-mime", "query", "default", MIME_TYPE])
      raise ConfigurationError, concise(result.stderr, "Could not inspect desktop URL handlers") unless result.success?

      result.stdout.to_s.strip
    end

    def desktop_entry
      <<~DESKTOP
        [Desktop Entry]
        Type=Application
        Name=WHOOP for Omarchy
        Comment=Return WHOOP authorization to the Omarchy plugin
        NoDisplay=true
        Terminal=false
        Exec="#{escape_exec(@helper_path)}" oauth-callback %u
        MimeType=#{MIME_TYPE};
      DESKTOP
    end

    def escape_exec(value)
      value.gsub(/["`$\\]/) { |character| "\\#{character}" }
    end

    def open_server
      remove_owned_socket
      server = UNIXServer.new(@socket_path)
      File.chmod(0o600, @socket_path)
      server
    end

    def read_callback(connection, deadline)
      payload = +""
      loop do
        wait_until_readable(connection, deadline)
        chunk = connection.read_nonblock(MAX_CALLBACK_BYTES + 1 - payload.bytesize, exception: false)
        next if chunk == :wait_readable
        break if chunk.nil?

        payload << chunk
        raise AuthError, "The WHOOP callback was unexpectedly large." if payload.bytesize > MAX_CALLBACK_BYTES
      end
      payload
    end

    def wait_until_readable(io, deadline)
      remaining = deadline - monotonic_time
      readable = remaining.positive? && IO.select([io], nil, nil, remaining)
      return if readable

      raise AuthError, "WHOOP authorization timed out. Confirm the browser opened WHOOP for Omarchy, then start setup again."
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def acquire_lock
      raise ConfigurationError, "XDG_RUNTIME_DIR is unavailable; WHOOP cannot receive the private OAuth callback." if @lock_path.nil?

      directory = File.dirname(@lock_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory)
      unless File.stat(directory).uid == Process.uid
        raise ConfigurationError, "The WHOOP runtime directory is not owned by the current user."
      end

      lock = File.open(@lock_path, File::RDWR | File::CREAT, 0o600)
      File.chmod(0o600, @lock_path)
      return lock if lock.flock(File::LOCK_EX | File::LOCK_NB)

      lock.close
      raise ConfigurationError, "Another WHOOP setup is already waiting for browser authorization."
    end

    def remove_owned_socket
      return unless @socket_path && File.socket?(@socket_path)
      return unless File.stat(@socket_path).uid == Process.uid

      File.unlink(@socket_path)
    end

    def validate_callback(value)
      callback = value.to_s.strip
      raise AuthError, "The WHOOP callback was empty." if callback.empty?
      raise AuthError, "The WHOOP callback contained invalid control characters." if callback.include?("\0") || callback.match?(/[\r\n]/)

      uri = URI(callback)
      expected = URI(REDIRECT_URI)
      unless uri.scheme == expected.scheme && uri.host == expected.host && uri.path == expected.path
        raise AuthError, "That callback URL does not match #{REDIRECT_URI}."
      end

      callback
    rescue URI::InvalidURIError
      raise AuthError, "That does not look like a complete WHOOP callback URL."
    end

    def atomic_write(path, content, mode:)
      temporary = "#{path}.tmp.#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, mode) { |file| file.write(content) }
      File.rename(temporary, path)
      File.chmod(mode, path)
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end

    def remove_user_associations
      [
        File.join(@config_home, "mimeapps.list"),
        File.join(@applications_dir, "mimeapps.list")
      ].uniq.each { |path| remove_association_from(path) }
    end

    def remove_association_from(path)
      return unless File.file?(path)

      section = ""
      changed = false
      lines = File.readlines(path, chomp: true).filter_map do |line|
        section = line if line.start_with?("[") && line.end_with?("]")
        next line unless ["[Default Applications]", "[Added Associations]"].include?(section)
        next line unless line.start_with?("#{MIME_TYPE}=")

        handlers = line.split("=", 2).last.to_s.split(";").reject(&:empty?)
        remaining = handlers.reject { |handler| handler == DESKTOP_ID }
        next line if remaining == handlers

        changed = true
        remaining.empty? ? nil : "#{MIME_TYPE}=#{remaining.join(';')};"
      end
      return unless changed

      mode = File.stat(path).mode & 0o777
      atomic_write(path, "#{lines.join("\n")}\n", mode: mode)
    end

    def execute!(argv, fallback)
      result = execute(argv)
      return result if result.success?

      raise ConfigurationError, concise(result.stderr, fallback)
    end

    def run_optional(argv)
      execute(argv)
    rescue ConfigurationError
      nil
    end

    def execute(argv)
      @runner.call(argv)
    rescue Errno::ENOENT => error
      raise ConfigurationError, "Required desktop command was not found: #{error.message}"
    end

    def run(argv)
      stdout, stderr, status = Open3.capture3(*argv)
      Result.new(stdout, stderr, status.success?)
    end

    def concise(value, fallback)
      line = value.to_s.lines.map(&:strip).find { |item| !item.empty? }
      line.nil? ? fallback : "#{fallback}: #{line[0, 180]}"
    end
  end
end
