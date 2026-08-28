# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  FakeStore = Struct.new(:bundle) do
    attr_reader :writes
    def read = bundle.dup
    def write(value)
      @writes ||= []
      @writes << value.dup
      self.bundle = value.dup
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
end

