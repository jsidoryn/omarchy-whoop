# frozen_string_literal: true

require_relative "test_helper"

class OAuthTest < Minitest::Test
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
    assert_equal "code-123", oauth.callback_code("whoop://omarchy/callback?code=code-123&state=Ab12Cd34", expected_state: "Ab12Cd34")
    assert_raises(OmarchyWhoop::AuthError) do
      oauth.callback_code("whoop://omarchy/callback?code=code-123&state=Wrong000", expected_state: "Ab12Cd34")
    end
  end
end

