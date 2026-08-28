# frozen_string_literal: true

require "fileutils"

module OmarchyWhoop
  class Client
    TOKEN_SKEW = 90

    def initialize(store: SecretStore.new, oauth: OAuth.new, api: Api.new, presenter: Presenter.new, clock: -> { Time.now.to_i }, lock_path: nil)
      @store = store
      @oauth = oauth
      @api = api
      @presenter = presenter
      @clock = clock
      @lock_path = lock_path || File.join(ENV.fetch("XDG_RUNTIME_DIR", "/tmp"), "omarchy-whoop-refresh.lock")
    end

    def valid_access_token
      with_lock { valid_access_token_unlocked }
    end

    def store_credentials(bundle)
      with_lock { @store.write(bundle) }
    end

    def snapshot
      token = valid_access_token
      payload = @api.snapshot(token)
      @presenter.snapshot(**payload)
    rescue HttpError => error
      raise unless error.status == 401
      expire_access_token
      payload = @api.snapshot(valid_access_token)
      @presenter.snapshot(**payload)
    end

    def disconnect
      with_lock do
        bundle = @store.read
        return true unless bundle

        begin
          @api.revoke(valid_access_token_unlocked(bundle))
        rescue Error, KeyError
          # Local deletion must remain possible when offline or already revoked.
        ensure
          @store.clear
        end
        true
      end
    end

    private

    def with_lock
      FileUtils.mkdir_p(File.dirname(@lock_path))
      File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    end

    def valid_access_token_unlocked(bundle = nil)
      bundle ||= @store.read
      raise AuthError, "WHOOP is not connected." unless bundle
      return bundle["access_token"] if bundle["access_token"] && bundle["expires_at"].to_i > @clock.call + TOKEN_SKEW

      tokens = @oauth.refresh(bundle)
      updated = bundle.merge(tokens).merge("expires_at" => @clock.call + tokens.fetch("expires_in").to_i)
      save_rotated_tokens(updated)
      updated.fetch("access_token")
    end

    def save_rotated_tokens(bundle)
      @store.write(bundle)
    rescue ConfigurationError => error
      raise AuthError, "WHOOP rotated its tokens, but the new credentials could not be saved. Unlock your keyring and reconnect WHOOP. (#{error.message})"
    end

    def expire_access_token
      with_lock do
        bundle = @store.read
        @store.write(bundle.merge("expires_at" => 0)) if bundle
      end
    end
  end
end
