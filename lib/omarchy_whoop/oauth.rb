# frozen_string_literal: true

require "digest"
require "openssl"
require "securerandom"
require "uri"

module OmarchyWhoop
  class OAuth
    AUTH_URL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token"
    SCOPES = %w[offline read:cycles read:recovery read:sleep].freeze
    MIN_STATE_LENGTH = 8

    def initialize(http: Http.new)
      @http = http
    end

    # WHOOP requires at least eight characters of state; more is strictly better.
    def self.generate_state = SecureRandom.alphanumeric(32)

    # RFC 7636 verifier: 32 random bytes, base64url without padding (43 characters).
    def self.generate_code_verifier = SecureRandom.urlsafe_base64(32)

    def authorization_url(client_id:, redirect_uri:, state:, code_verifier:)
      raise ArgumentError, "WHOOP OAuth state must be at least #{MIN_STATE_LENGTH} characters" if state.to_s.length < MIN_STATE_LENGTH

      uri = URI(AUTH_URL)
      uri.query = URI.encode_www_form(
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: SCOPES.join(" "),
        state: state,
        code_challenge: code_challenge(code_verifier),
        code_challenge_method: "S256"
      )
      uri.to_s
    end

    def callback_code(callback, expected_state:, redirect_uri:)
      uri = URI(callback.to_s.strip)
      expected = URI(redirect_uri)
      unless uri.scheme == expected.scheme && uri.host == expected.host && uri.path == expected.path
        raise AuthError, "That callback URL does not match #{redirect_uri}."
      end
      params = URI.decode_www_form(uri.query.to_s).to_h
      raise AuthError, "WHOOP returned an OAuth error: #{params['error']}" if params["error"]
      raise AuthError, "The callback state did not match. Start setup again." unless OpenSSL.secure_compare(params["state"].to_s, expected_state.to_s)
      raise AuthError, "The callback URL did not contain an authorization code." if params["code"].to_s.empty?

      params.fetch("code")
    rescue URI::InvalidURIError
      raise AuthError, "That does not look like the complete WHOOP callback URL."
    end

    def exchange(client_id:, client_secret:, redirect_uri:, code:, code_verifier:)
      @http.request(:post, TOKEN_URL, form: {
        grant_type: "authorization_code",
        code: code,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        code_verifier: code_verifier
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

    # S256 challenge: base64url of the SHA-256 digest, without padding.
    def code_challenge(code_verifier)
      Digest::SHA256.base64digest(code_verifier).tr("+/", "-_").delete("=")
    end
  end
end
