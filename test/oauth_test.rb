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

  def test_authorization_url_uses_state_pkce_and_minimal_scopes
    oauth = OmarchyWhoop::OAuth.new(http: nil)
    redirect_uri = OmarchyWhoop::CallbackHandler::REDIRECT_URI
    verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    url = URI(oauth.authorization_url(client_id: "client", redirect_uri: redirect_uri, state: "Ab12Cd34", code_verifier: verifier))
    params = URI.decode_www_form(url.query).to_h

    assert_equal "client", params.fetch("client_id")
    assert_equal redirect_uri, params.fetch("redirect_uri")
    assert_equal "Ab12Cd34", params.fetch("state")
    assert_equal "offline read:cycles read:recovery read:sleep", params.fetch("scope")
    # RFC 7636 appendix B test vector.
    assert_equal "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", params.fetch("code_challenge")
    assert_equal "S256", params.fetch("code_challenge_method")
    assert_raises(ArgumentError) do
      oauth.authorization_url(client_id: "client", redirect_uri: redirect_uri, state: "short", code_verifier: verifier)
    end
  end

  def test_generated_state_and_verifier_are_long_and_random
    state = OmarchyWhoop::OAuth.generate_state
    verifier = OmarchyWhoop::OAuth.generate_code_verifier

    assert_equal 32, state.length
    assert_match(/\A[A-Za-z0-9]+\z/, state)
    assert_equal 43, verifier.length
    assert_match(/\A[A-Za-z0-9_-]+\z/, verifier)
    refute state == OmarchyWhoop::OAuth.generate_state
  end

  def test_callback_requires_matching_state
    oauth = OmarchyWhoop::OAuth.new(http: nil)
    redirect_uri = OmarchyWhoop::CallbackHandler::REDIRECT_URI
    assert_equal "code-123", oauth.callback_code("#{redirect_uri}?code=code-123&state=Ab12Cd34", expected_state: "Ab12Cd34", redirect_uri: redirect_uri)
    assert_raises(OmarchyWhoop::AuthError) do
      oauth.callback_code("#{redirect_uri}?code=code-123&state=Wrong000", expected_state: "Ab12Cd34", redirect_uri: redirect_uri)
    end
    assert_raises(OmarchyWhoop::AuthError) do
      oauth.callback_code("https://example.com/callback?code=code-123&state=Ab12Cd34", expected_state: "Ab12Cd34", redirect_uri: redirect_uri)
    end
  end

  def test_token_exchange_uses_whoops_documented_form_encoding
    http = RecordingHttp.new
    oauth = OmarchyWhoop::OAuth.new(http: http)

    oauth.exchange(client_id: "id", client_secret: "secret", redirect_uri: OmarchyWhoop::CallbackHandler::REDIRECT_URI, code: "code", code_verifier: "verifier")

    args, kwargs = http.request_args
    assert_equal [:post, OmarchyWhoop::OAuth::TOKEN_URL], args
    assert_equal "authorization_code", kwargs.fetch(:form).fetch(:grant_type)
    assert_equal "verifier", kwargs.fetch(:form).fetch(:code_verifier)
    refute kwargs.key?(:json)
  end
end
