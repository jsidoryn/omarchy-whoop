# frozen_string_literal: true

require_relative "test_helper"

class PresenterTest < Minitest::Test
  def test_normalizes_scored_whoop_payloads
    cycle = {"id" => 93_845, "start" => "2026-08-28T21:30:00Z", "score_state" => "SCORED", "score" => {"strain" => 12.7, "kilojoule" => 8_288.3, "average_heart_rate" => 68, "max_heart_rate" => 151}}
    recovery = {"cycle_id" => 93_845, "created_at" => "2026-08-29T06:10:00Z", "score_state" => "SCORED", "score" => {"user_calibrating" => false, "recovery_score" => 82, "resting_heart_rate" => 48, "hrv_rmssd_milli" => 61.4, "spo2_percentage" => 97.2, "skin_temp_celsius" => 33.5}}
    sleep = {"score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 87, "sleep_consistency_percentage" => 81, "sleep_efficiency_percentage" => 92.5, "stage_summary" => {"total_in_bed_time_milli" => 28_800_000, "total_awake_time_milli" => 1_800_000, "total_light_sleep_time_milli" => 13_000_000, "total_slow_wave_sleep_time_milli" => 6_000_000, "total_rem_sleep_time_milli" => 8_000_000, "disturbance_count" => 8}, "sleep_needed" => {"baseline_milli" => 28_000_000, "need_from_sleep_debt_milli" => 1_200_000, "need_from_recent_strain_milli" => 600_000, "need_from_recent_nap_milli" => 0}}}
    history = {"records" => [recovery, recovery.merge("created_at" => "2026-08-28T06:10:00Z", "score" => recovery.fetch("score").merge("recovery_score" => 67))]}
    cycle_history = {"records" => [cycle, cycle.merge("id" => 93_844, "start" => "2026-08-27T21:30:00Z", "score" => cycle.fetch("score").merge("strain" => 9.4))]}
    sleep_history = {"records" => [
      sleep.merge("start" => "2026-08-27T22:25:00Z", "end" => "2026-08-28T06:25:00Z", "nap" => false),
      sleep.merge("start" => "2026-08-27T16:00:00Z", "end" => "2026-08-27T16:40:00Z", "nap" => true, "score" => sleep.fetch("score").merge("sleep_performance_percentage" => 42)),
      sleep.merge("start" => "2026-08-26T22:30:00Z", "end" => "2026-08-27T06:30:00Z", "nap" => false, "score" => sleep.fetch("score").merge("sleep_performance_percentage" => 79))
    ]}

    result = OmarchyWhoop::Presenter.new.snapshot(cycle:, recovery:, sleep:, history:, cycle_history:, sleep_history:, fetched_at: Time.parse("2026-08-29T12:00:00Z"))

    assert_equal "ok", result.fetch("state")
    assert_equal true, result.fetch("connected")
    assert_equal 82, result.dig("recovery", "score")
    assert_equal 61.4, result.dig("recovery", "hrvMs")
    assert_equal 12.7, result.dig("cycle", "strain")
    assert_equal 87, result.dig("sleep", "performance")
    assert_in_delta 7.5, result.dig("sleep", "actualHours"), 0.01
    assert_equal [67, 82], result.dig("trends", "recovery").map { |day| day.fetch("value") }
    assert_equal [9.4, 12.7], result.dig("trends", "strain").map { |day| day.fetch("value") }
    assert_equal [79, 87], result.dig("trends", "sleep").map { |day| day.fetch("value") }
  end

  def test_pending_recovery_is_a_first_class_state
    result = OmarchyWhoop::Presenter.new.snapshot(
      cycle: {"id" => 1, "score_state" => "SCORED", "score" => {"strain" => 4.2}},
      recovery: {"cycle_id" => 1, "score_state" => "PENDING_SCORE"},
      sleep: {"score_state" => "PENDING_SCORE"},
      history: {"records" => []}
    )

    assert_equal "pending", result.fetch("state")
    assert_nil result.dig("recovery", "score")
    assert_match(/calculating/i, result.fetch("message"))
  end

  def test_demo_scenarios_are_complete_and_clearly_labelled
    %w[primed balanced strained pending].each do |scenario|
      result = OmarchyWhoop::Demo.snapshot(scenario)
      assert_equal "demo", result.fetch("mode")
      assert_equal false, result.fetch("connected")
      assert_equal scenario, result.fetch("demoScenario")
      assert_equal %w[recovery sleep strain], result.fetch("trends").keys
      result.fetch("trends").each_value { |trend| assert_equal 7, trend.length }
      assert result.key?("recovery")
      assert result.key?("cycle")
      assert result.key?("sleep")
    end
  end

  def test_week_is_oldest_first_even_when_whoop_returns_newest_first
    recovery = lambda do |date, score|
      {"created_at" => date, "score_state" => "SCORED", "score" => {"recovery_score" => score}}
    end
    result = OmarchyWhoop::Presenter.new.snapshot(
      cycle: {"id" => 1},
      recovery: recovery.call("2026-08-29T06:00:00Z", 80),
      sleep: {"score_state" => "PENDING_SCORE"},
      history: {"records" => [recovery.call("2026-08-29T06:00:00Z", 80), recovery.call("2026-08-28T06:00:00Z", 65)]},
      fetched_at: Time.parse("2026-08-29T12:00:00Z")
    )

    assert_equal [65, 80], result.dig("trends", "recovery").map { |day| day.fetch("value") }
  end

  def test_trends_include_only_the_last_seven_calendar_days
    fetched_at = Time.parse("2026-08-29T12:00:00Z")
    recovery_records = (0..7).map do |offset|
      date = (fetched_at - offset * 86_400).iso8601
      {"created_at" => date, "score_state" => "SCORED", "score" => {"recovery_score" => 80 - offset}}
    end
    cycle_records = (0..7).map do |offset|
      date = (fetched_at - offset * 86_400).iso8601
      {"id" => 100 - offset, "start" => date, "score_state" => "SCORED", "score" => {"strain" => 10.0 + offset}}
    end
    sleep_records = (0..7).map do |offset|
      wake = fetched_at - offset * 86_400
      {"start" => (wake - 8 * 3600).iso8601, "end" => wake.iso8601, "nap" => false, "score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 90 - offset}}
    end

    result = OmarchyWhoop::Presenter.new.snapshot(
      cycle: cycle_records.first,
      recovery: recovery_records.first,
      sleep: sleep_records.first,
      history: {"records" => recovery_records},
      cycle_history: {"records" => cycle_records},
      sleep_history: {"records" => sleep_records},
      fetched_at:
    )

    assert_equal [74, 75, 76, 77, 78, 79, 80], result.dig("trends", "recovery").map { |day| day.fetch("value") }
    assert_equal [16.0, 15.0, 14.0, 13.0, 12.0, 11.0, 10.0], result.dig("trends", "strain").map { |day| day.fetch("value") }
    assert_equal [84, 85, 86, 87, 88, 89, 90], result.dig("trends", "sleep").map { |day| day.fetch("value") }
    assert_equal "2026-08-29T12:00:00Z", result.dig("trends", "sleep").last.fetch("date")
  end

  def test_strain_trend_uses_cycle_end_date_and_snapshot_date_for_open_cycle
    fetched_at = Time.parse("2026-08-30T23:00:00Z")
    cycle_records = [
      {"id" => 3, "start" => "2026-08-30T14:01:03Z", "end" => nil, "score_state" => "SCORED", "score" => {"strain" => 0.3}},
      {"id" => 2, "start" => "2026-08-25T13:51:59Z", "end" => "2026-08-26T13:47:59Z", "score_state" => "SCORED", "score" => {"strain" => 11.8}},
      {"id" => 1, "start" => "2026-08-24T14:44:33Z", "end" => "2026-08-25T13:51:59Z", "score_state" => "SCORED", "score" => {"strain" => 4.1}}
    ]

    result = OmarchyWhoop::Presenter.new.snapshot(
      cycle: cycle_records.first,
      recovery: {"score_state" => "PENDING_SCORE"},
      sleep: {"score_state" => "PENDING_SCORE"},
      history: {"records" => []},
      cycle_history: {"records" => cycle_records},
      sleep_history: {"records" => []},
      fetched_at:
    )

    assert_equal [
      "2026-08-25T13:51:59Z",
      "2026-08-26T13:47:59Z",
      "2026-08-30T23:00:00Z"
    ], result.dig("trends", "strain").map { |day| day.fetch("date") }
  end

  def test_snapshot_marks_only_the_unavailable_trend
    result = OmarchyWhoop::Presenter.new.snapshot(
      cycle: {"id" => 1, "start" => "2026-08-29T00:00:00Z"},
      recovery: {"cycle_id" => 1, "score_state" => "SCORED", "score" => {"recovery_score" => 80}},
      sleep: {"score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 90}},
      history: {"records" => []},
      cycle_history: {"records" => []},
      sleep_history: {"records" => [], "unavailable" => true},
      fetched_at: Time.parse("2026-08-29T12:00:00Z")
    )

    assert_equal false, result.dig("trendUnavailable", "recovery")
    assert_equal true, result.dig("trendUnavailable", "sleep")
    assert_equal false, result.dig("trendUnavailable", "strain")
  end
end
