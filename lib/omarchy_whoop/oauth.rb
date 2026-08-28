# frozen_string_literal: true

require "uri"

module OmarchyWhoop
  class OAuth
    AUTH_URL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
    SCOPES = %w[offline read:cycles read:recovery read:sleep].freeze

    def initialize(http: Http.new)
      @http = http
    end

    def authorization_url(client_id:, redirect_uri:, state:)
      raise ArgumentError, "WHOOP OAuth state must be exactly eight characters" unless state.to_s.length == 8

      uri = URI(AUTH_URL)
      uri.query = URI.encode_www_form(
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: SCOPES.join(" "),
        state: state
      )
      uri.to_s
    end

    def callback_code(callback, expected_state:)
      uri = URI(callback.to_s.strip)
      params = URI.decode_www_form(uri.query.to_s).to_h
      raise AuthError, "WHOOP returned an OAuth error: #{params['error']}" if params["error"]
      raise AuthError, "The callback state did not match. Start setup again." unless secure_equal?(params["state"], expected_state)
      raise AuthError, "The callback URL did not contain an authorization code." if params["code"].to_s.empty?

      params.fetch("code")
    rescue URI::InvalidURIError
      raise AuthError, "That does not look like the complete WHOOP callback URL."
    end

    def exchange(client_id:, client_secret:, redirect_uri:, code:)
      @http.request(:post, TOKEN_URL, form: {
        grant_type: "authorization_code",
        code: code,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri
      })
    end

    def refresh(bundle)
      @http.request(:post, TOKEN_URL, form: {
        grant_type: "refresh_token",
        refresh_token: bundle.fetch("refresh_token"),
        client_id: bundle.fetch("client_id"),
        client_secret: bundle.fetch("client_secret"),
        scope: "offline"
      })
    rescue KeyError
      raise ConfigurationError, "The WHOOP keyring entry is incomplete. Reconnect WHOOP."
    end

    private

    def secure_equal?(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end
  end
end

