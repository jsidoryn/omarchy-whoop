# frozen_string_literal: true

module OmarchyWhoop
  class Error < StandardError; end
  class AuthError < Error; end
  class ConfigurationError < Error; end

  class HttpError < Error
    attr_reader :status, :body

    def initialize(message, status:, body: "")
      super(message)
      @status = status
      @body = body
    end
  end
end

