# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  FakeStore = Struct.new(:bundle) do
    attr_reader :writes
    def read = bundle&.dup
    def write(value)
      @writes ||= []
      @writes << value.dup
      self.bundle = value.dup
    end
    def clear
      self.bundle = nil
      true
    end
  end

  class FakeOAuth
    attr_reader :refreshes
    def initialize
      @refreshes = []
    end
    def refresh(bundle)
      @refreshes << bundle
      {"access_token" => "fresh-access", "refresh_token" => "fresh-refresh", "expires_in" => 3600, "scope" => bundle["scope"]}
    end
  end

  class BlockingOAuth < FakeOAuth
    def initialize(started:, release:)
      super()
      @started = started
      @release = release
    end

    def refresh(bundle)
      @started << true
      @release.pop
      super
    end
  end

  class FakeApi
    attr_reader :revoked
    def revoke(token)
      @revoked = token
      true
    end
  end

  class RetryApi
    attr_reader :tokens

    def initialize
      @tokens = []
    end

    def snapshot(token)
      @tokens << token
      raise OmarchyWhoop::HttpError.new("expired", status: 401) if @tokens.length == 1

      {
        cycle: {"id" => 1},
        recovery: {"score_state" => "PENDING_SCORE"},
        sleep: {"score_state" => "PENDING_SCORE"},
        history: {"records" => []}
      }
    end
  end

  class FailingWriteStore < FakeStore
    def write(_value)
      raise OmarchyWhoop::ConfigurationError, "collection is locked"
    end
  end

  def test_refresh_replaces_the_entire_rotating_token_bundle
    store = FakeStore.new({"client_id" => "id", "client_secret" => "secret", "access_token" => "old", "refresh_token" => "old-refresh", "expires_at" => 0, "scope" => OmarchyWhoop::OAuth::SCOPES.join(" ")})
    oauth = FakeOAuth.new
    client = OmarchyWhoop::Client.new(store:, oauth:, api: nil, clock: -> { 1_000 })

    token = client.valid_access_token

    assert_equal "fresh-access", token
    assert_equal "fresh-refresh", store.bundle.fetch("refresh_token")
    assert_equal 4_600, store.bundle.fetch("expires_at")
    assert_equal 1, store.writes.length
  end

  def test_disconnect_waits_for_refresh_then_clears_the_rotated_bundle
    Dir.mktmpdir do |directory|
      store = FakeStore.new({"client_id" => "id", "client_secret" => "secret", "access_token" => "old", "refresh_token" => "old-refresh", "expires_at" => 0})
      started = Queue.new
      release = Queue.new
      api = FakeApi.new
      client = OmarchyWhoop::Client.new(
        store: store,
        oauth: BlockingOAuth.new(started: started, release: release),
        api: api,
        clock: -> { 1_000 },
        lock_path: File.join(directory, "refresh.lock")
      )

      refresh_thread = Thread.new { client.valid_access_token }
      started.pop
      disconnect_thread = Thread.new { client.disconnect }
      release << true
      refresh_thread.value
      disconnect_thread.value

      assert_nil store.bundle
      assert_equal "fresh-access", api.revoked
    end
  end

  def test_disconnect_refreshes_an_expired_token_before_revoking
    Dir.mktmpdir do |directory|
      store = FakeStore.new({"client_id" => "id", "client_secret" => "secret", "access_token" => "expired", "refresh_token" => "old-refresh", "expires_at" => 0})
      api = FakeApi.new
      client = OmarchyWhoop::Client.new(store: store, oauth: FakeOAuth.new, api: api, clock: -> { 1_000 }, lock_path: File.join(directory, "refresh.lock"))

      client.disconnect

      assert_equal "fresh-access", api.revoked
      assert_nil store.bundle
    end
  end

  def test_snapshot_retries_once_with_a_fresh_token_after_401
    Dir.mktmpdir do |directory|
      store = FakeStore.new({"client_id" => "id", "client_secret" => "secret", "access_token" => "old", "refresh_token" => "old-refresh", "expires_at" => 10_000})
      api = RetryApi.new
      client = OmarchyWhoop::Client.new(store: store, oauth: FakeOAuth.new, api: api, clock: -> { 1_000 }, lock_path: File.join(directory, "refresh.lock"))

      result = client.snapshot

      assert_equal "pending", result.fetch("state")
      assert_equal ["old", "fresh-access"], api.tokens
      assert_equal "fresh-refresh", store.bundle.fetch("refresh_token")
    end
  end

  def test_rotated_token_write_failure_requires_reconnection
    Dir.mktmpdir do |directory|
      store = FailingWriteStore.new({"client_id" => "id", "client_secret" => "secret", "access_token" => "old", "refresh_token" => "old-refresh", "expires_at" => 0})
      client = OmarchyWhoop::Client.new(store: store, oauth: FakeOAuth.new, api: nil, clock: -> { 1_000 }, lock_path: File.join(directory, "refresh.lock"))

      error = assert_raises(OmarchyWhoop::AuthError) { client.valid_access_token }

      assert_match(/rotated its tokens/i, error.message)
      assert_match(/reconnect WHOOP/i, error.message)
    end
  end
end
