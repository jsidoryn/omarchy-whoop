# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OmarchyWhoop
  class Http
    USER_AGENT = "omarchy-whoop/0.1"

    def request(method, url, headers: {}, form: nil, json: nil)
      uri = URI(url)
      request = request_class(method).new(uri)
      request["User-Agent"] = USER_AGENT
      headers.each { |key, value| request[key] = value }
      request.set_form_data(form) if form
      if json
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(json)
      end

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end

      body = response.body.to_s
      return body.empty? ? {} : JSON.parse(body) if response.code.to_i.between?(200, 299)

      raise HttpError.new(error_message(response.code.to_i, body), status: response.code.to_i, body: body)
    rescue JSON::ParserError
      raise HttpError.new("WHOOP returned an unreadable response", status: response&.code.to_i, body: response&.body.to_s)
    rescue SocketError, SystemCallError, Timeout::Error => error
      raise HttpError.new("Could not reach WHOOP: #{error.message}", status: 0)
    end

    private

    def request_class(method)
      {get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete}.fetch(method.to_sym)
    end

    def error_message(status, body)
      parsed = JSON.parse(body) rescue {}
      detail = parsed["error_description"] || parsed["message"] || parsed["error"]
      detail = detail.to_s.strip
      detail.empty? ? "WHOOP request failed (HTTP #{status})" : "WHOOP request failed: #{detail[0, 180]}"
    end
  end
end

