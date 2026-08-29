# frozen_string_literal: true

require_relative "test_helper"

class ApiTest < Minitest::Test
  class FakeHttp
    attr_reader :urls

    def initialize(responses)
      @responses = responses.dup
      @urls = []
    end

    def request(_method, url, headers:)
      @urls << url
      assert_equal "Bearer access-token", headers.fetch("Authorization")
      response = @responses.shift
      raise response if response.is_a?(Exception)
      response
    end

    private

    def assert_equal(expected, actual)
      raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
    end
  end

  def test_snapshot_fetches_collection_data_for_each_seven_day_trend
    cycles = {"records" => [{"id" => 7}, {"id" => 6}]}
    recovery = {"cycle_id" => 7, "score_state" => "SCORED", "score" => {"recovery_score" => 80}}
    sleep = {"cycle_id" => 7, "score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 90}}
    recoveries = {"records" => [recovery]}
    sleeps = {"records" => [sleep]}
    http = FakeHttp.new([cycles, recovery, sleep, recoveries, sleeps])

    result = OmarchyWhoop::Api.new(http:).snapshot("access-token")

    assert_equal cycles, result.fetch(:cycle_history)
    assert_equal recoveries, result.fetch(:history)
    assert_equal sleeps, result.fetch(:sleep_history)
    assert_equal [
      "https://api.prod.whoop.com/developer/v2/cycle?limit=25",
      "https://api.prod.whoop.com/developer/v2/cycle/7/recovery",
      "https://api.prod.whoop.com/developer/v2/cycle/7/sleep",
      "https://api.prod.whoop.com/developer/v2/recovery?limit=25",
      "https://api.prod.whoop.com/developer/v2/activity/sleep?limit=25"
    ], http.urls
  end

  def test_snapshot_keeps_direct_scores_when_supplementary_sleep_history_fails
    cycles = {"records" => [{"id" => 7}]}
    recovery = {"cycle_id" => 7, "score_state" => "SCORED", "score" => {"recovery_score" => 80}}
    sleep = {"cycle_id" => 7, "score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 90}}
    recoveries = {"records" => [recovery]}
    unavailable = OmarchyWhoop::HttpError.new("WHOOP unavailable", status: 503)
    http = FakeHttp.new([cycles, recovery, sleep, recoveries, unavailable])

    result = OmarchyWhoop::Api.new(http:).snapshot("access-token")

    assert_equal recovery, result.fetch(:recovery)
    assert_equal sleep, result.fetch(:sleep)
    assert_equal({"records" => [], "unavailable" => true}, result.fetch(:sleep_history))
  end

  def test_snapshot_does_not_hide_supplementary_history_rate_limits
    cycles = {"records" => [{"id" => 7}]}
    recovery = {"cycle_id" => 7, "score_state" => "SCORED", "score" => {"recovery_score" => 80}}
    sleep = {"cycle_id" => 7, "score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 90}}
    rate_limited = OmarchyWhoop::HttpError.new("WHOOP rate limited", status: 429)
    http = FakeHttp.new([cycles, recovery, sleep, {"records" => [recovery]}, rate_limited])

    error = assert_raises(OmarchyWhoop::HttpError) do
      OmarchyWhoop::Api.new(http:).snapshot("access-token")
    end

    assert_equal 429, error.status
  end
end
