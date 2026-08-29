# frozen_string_literal: true

module OmarchyWhoop
  class Api
    BASE_URL = "https://api.prod.whoop.com/developer/v2"

    def initialize(http: Http.new)
      @http = http
    end

    def snapshot(access_token)
      cycle_collection = get("/cycle?limit=10", access_token)
      cycle = Array(cycle_collection["records"]).first
      raise Error, "WHOOP has not returned a physiological cycle yet." unless cycle

      id = cycle.fetch("id")
      recovery = get_optional("/cycle/#{id}/recovery", access_token)
      sleep = get_optional("/cycle/#{id}/sleep", access_token)
      history = get("/recovery?limit=10", access_token)
      sleep_history = get("/activity/sleep?limit=14", access_token)
      {
        cycle: cycle,
        recovery: recovery || {"cycle_id" => id, "score_state" => "PENDING_SCORE"},
        sleep: sleep || {"score_state" => "PENDING_SCORE"},
        history: history,
        cycle_history: cycle_collection,
        sleep_history: sleep_history
      }
    end

    def revoke(access_token)
      @http.request(:delete, "#{BASE_URL}/user/access", headers: authorization(access_token))
      true
    end

    private

    def get(path, token)
      @http.request(:get, "#{BASE_URL}#{path}", headers: authorization(token))
    end

    def get_optional(path, token)
      get(path, token)
    rescue HttpError => error
      raise unless error.status == 404
      nil
    end

    def authorization(token) = {"Authorization" => "Bearer #{token}"}
  end
end
