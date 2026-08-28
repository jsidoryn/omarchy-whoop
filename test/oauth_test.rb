# frozen_string_literal: true

require_relative "test_helper"

class OAuthTest < Minitest::Test
  class RecordingHttp
    attr_reader :request_args

    def request(*args, **kwargs)
      @request_args = [args, kwargs]
      {"access_token" => "access", "refresh_token" => "refresh", "expires_in" => 3600}
    end
  end

  def test_authorization_url_uses_eight_character_state_and_minimal_scopes
    oauth = OmarchyWhoop::OAuth.new(http: nil)
    url = URI(oauth.authorization_url(client_id: "client", redirect_uri: "whoop://omarchy/callback", state: "Ab12Cd34"))
    params = URI.decode_www_form(url.query).to_h

    assert_equal "client", params.fetch("client_id")
    assert_equal "whoop://omarchy/callback", params.fetch("redirect_uri")
    assert_equal "Ab12Cd34", params.fetch("state")
    assert_equal "offline read:cycles read:recovery read:sleep", params.fetch("scope")
    assert_raises(ArgumentError) { oauth.authorization_url(client_id: "client", redirect_uri: "whoop://omarchy/callback", state: "short") }
  end

  def test_callback_requires_matching_state
    oauth = OmarchyWhoop::OAuth.new(http: nil)
    redirect_uri = "whoop://omarchy/callback"
    assert_equal "code-123", oauth.callback_code("whoop://omarchy/callback?code=code-123&state=Ab12Cd34", expected_state: "Ab12Cd34", redirect_uri: redirect_uri)
    assert_raises(OmarchyWhoop::AuthError) do
      oauth.callback_code("whoop://omarchy/callback?code=code-123&state=Wrong000", expected_state: "Ab12Cd34", redirect_uri: redirect_uri)
    end
    assert_raises(OmarchyWhoop::AuthError) do
      oauth.callback_code("https://example.com/callback?code=code-123&state=Ab12Cd34", expected_state: "Ab12Cd34", redirect_uri: redirect_uri)
    end
  end

  def test_token_exchange_uses_whoops_documented_form_encoding
    http = RecordingHttp.new
    oauth = OmarchyWhoop::OAuth.new(http: http)

    oauth.exchange(client_id: "id", client_secret: "secret", redirect_uri: "whoop://omarchy/callback", code: "code")

    args, kwargs = http.request_args
    assert_equal [:post, OmarchyWhoop::OAuth::TOKEN_URL], args
    assert_equal "authorization_code", kwargs.fetch(:form).fetch(:grant_type)
    refute kwargs.key?(:json)
  end
end
