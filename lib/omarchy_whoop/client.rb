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
      with_lock do
        bundle = @store.read
        raise AuthError, "WHOOP is not connected." unless bundle
        return bundle["access_token"] if bundle["access_token"] && bundle["expires_at"].to_i > @clock.call + TOKEN_SKEW

        tokens = @oauth.refresh(bundle)
        updated = bundle.merge(tokens).merge("expires_at" => @clock.call + tokens.fetch("expires_in").to_i)
        @store.write(updated)
        updated.fetch("access_token")
      end
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
      bundle = @store.read
      if bundle && bundle["access_token"]
        begin
          @api.revoke(bundle["access_token"])
        rescue HttpError
          # Local deletion must remain possible when offline or already revoked.
        end
      end
      @store.clear
    end

    private

    def with_lock
      FileUtils.mkdir_p(File.dirname(@lock_path))
      File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      end
    end

    def expire_access_token
      with_lock do
        bundle = @store.read
        @store.write(bundle.merge("expires_at" => 0)) if bundle
      end
    end
  end
end
