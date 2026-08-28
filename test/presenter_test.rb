# frozen_string_literal: true

require_relative "test_helper"

class PresenterTest < Minitest::Test
  def test_normalizes_scored_whoop_payloads
    cycle = {"id" => 93_845, "start" => "2026-08-28T21:30:00Z", "score_state" => "SCORED", "score" => {"strain" => 12.7, "kilojoule" => 8_288.3, "average_heart_rate" => 68, "max_heart_rate" => 151}}
    recovery = {"cycle_id" => 93_845, "created_at" => "2026-08-29T06:10:00Z", "score_state" => "SCORED", "score" => {"user_calibrating" => false, "recovery_score" => 82, "resting_heart_rate" => 48, "hrv_rmssd_milli" => 61.4, "spo2_percentage" => 97.2, "skin_temp_celsius" => 33.5}}
    sleep = {"score_state" => "SCORED", "score" => {"sleep_performance_percentage" => 87, "sleep_consistency_percentage" => 81, "sleep_efficiency_percentage" => 92.5, "stage_summary" => {"total_in_bed_time_milli" => 28_800_000, "total_awake_time_milli" => 1_800_000, "total_light_sleep_time_milli" => 13_000_000, "total_slow_wave_sleep_time_milli" => 6_000_000, "total_rem_sleep_time_milli" => 8_000_000, "disturbance_count" => 8}, "sleep_needed" => {"baseline_milli" => 28_000_000, "need_from_sleep_debt_milli" => 1_200_000, "need_from_recent_strain_milli" => 600_000, "need_from_recent_nap_milli" => 0}}}
    history = {"records" => [recovery, recovery.merge("created_at" => "2026-08-28T06:10:00Z", "score" => recovery.fetch("score").merge("recovery_score" => 67))]}

    result = OmarchyWhoop::Presenter.new.snapshot(cycle:, recovery:, sleep:, history:)

    assert_equal "ok", result.fetch("state")
    assert_equal true, result.fetch("connected")
    assert_equal 82, result.dig("recovery", "score")
    assert_equal 61.4, result.dig("recovery", "hrvMs")
    assert_equal 12.7, result.dig("cycle", "strain")
    assert_equal 87, result.dig("sleep", "performance")
    assert_in_delta 7.5, result.dig("sleep", "actualHours"), 0.01
    assert_equal [67, 82], result.fetch("week").map { |day| day.fetch("score") }
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
      assert_equal 7, result.fetch("week").length
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
      history: {"records" => [recovery.call("2026-08-29T06:00:00Z", 80), recovery.call("2026-08-28T06:00:00Z", 65)]}
    )

    assert_equal [65, 80], result.fetch("week").map { |day| day.fetch("score") }
  end
end
