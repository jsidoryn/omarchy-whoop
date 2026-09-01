# frozen_string_literal: true

require "time"
require "date"

module OmarchyWhoop
  class Presenter
    def snapshot(cycle:, recovery:, sleep:, history:, cycle_history: {"records" => []}, sleep_history: {"records" => []}, fetched_at: Time.now.utc)
      recovery_state = recovery["score_state"].to_s
      score = recovery_state == "SCORED" ? recovery["score"] || {} : {}
      sleep_score = sleep["score_state"].to_s == "SCORED" ? sleep["score"] || {} : {}
      stage = sleep_score["stage_summary"] || {}
      needed = sleep_score["sleep_needed"] || {}
      calibrating = score["user_calibrating"] == true
      state = recovery_state == "SCORED" && !calibrating ? "ok" : "pending"
      oldest_trend_date = fetched_at.getlocal.to_date - 6

      {
        "schemaVersion" => 1,
        "state" => state,
        "mode" => "live",
        "connected" => true,
        "message" => state == "ok" ? "Live WHOOP data" : pending_message(recovery_state, calibrating),
        "fetchedAt" => fetched_at.iso8601,
        "demoScenario" => nil,
        "recovery" => {
          "score" => number(score["recovery_score"], integer: true),
          "scoreState" => recovery_state.empty? ? "PENDING_SCORE" : recovery_state,
          "calibrating" => calibrating,
          "hrvMs" => number(score["hrv_rmssd_milli"], precision: 1),
          "restingHeartRate" => number(score["resting_heart_rate"], integer: true),
          "spo2" => number(score["spo2_percentage"], precision: 1),
          "skinTempC" => number(score["skin_temp_celsius"], precision: 1)
        },
        "cycle" => {
          "id" => cycle["id"],
          "start" => cycle["start"],
          "strain" => number(cycle.dig("score", "strain"), precision: 1),
          "kilojoule" => number(cycle.dig("score", "kilojoule"), integer: true),
          "averageHeartRate" => number(cycle.dig("score", "average_heart_rate"), integer: true),
          "maxHeartRate" => number(cycle.dig("score", "max_heart_rate"), integer: true)
        },
        "sleep" => {
          "scoreState" => sleep["score_state"].to_s,
          "performance" => number(sleep_score["sleep_performance_percentage"], integer: true),
          "consistency" => number(sleep_score["sleep_consistency_percentage"], integer: true),
          "efficiency" => number(sleep_score["sleep_efficiency_percentage"], precision: 1),
          "actualHours" => hours(sleep_total(stage)),
          "neededHours" => hours(needed_total(needed)),
          "disturbances" => number(stage["disturbance_count"], integer: true),
          "lightHours" => hours(stage["total_light_sleep_time_milli"]),
          "slowWaveHours" => hours(stage["total_slow_wave_sleep_time_milli"]),
          "remHours" => hours(stage["total_rem_sleep_time_milli"])
        },
        "trends" => {
          "recovery" => scored_trend(history, date_key: "created_at", precision: 0, oldest_date: oldest_trend_date) { |item| item.dig("score", "recovery_score") },
          "sleep" => scored_trend(sleep_history, date_key: "end", precision: 0, oldest_date: oldest_trend_date, skip_naps: true) { |item| item.dig("score", "sleep_performance_percentage") },
          "strain" => scored_trend(cycle_history, date_key: "start", precision: 1, oldest_date: oldest_trend_date) { |item| item.dig("score", "strain") }
        },
        "trendUnavailable" => {
          "recovery" => history["unavailable"] == true,
          "sleep" => sleep_history["unavailable"] == true,
          "strain" => false
        }
      }
    end

    private

    # precision 0 yields an Integer, so JSON shows 82 rather than 82.0.
    def number(value, integer: false, precision: nil)
      return nil if value.nil?
      numeric = Float(value)
      return numeric.round if integer || precision == 0
      return numeric.round(precision) if precision
      numeric
    rescue ArgumentError, TypeError
      nil
    end

    def hours(milliseconds)
      value = number(milliseconds)
      value.nil? ? nil : (value / 3_600_000.0).round(2)
    end

    def sleep_total(stage)
      %w[total_light_sleep_time_milli total_slow_wave_sleep_time_milli total_rem_sleep_time_milli].sum { |key| number(stage[key]) || 0 }
    end

    def needed_total(needed)
      %w[baseline_milli need_from_sleep_debt_milli need_from_recent_strain_milli need_from_recent_nap_milli].sum { |key| number(needed[key]) || 0 }
    end

    def scored_trend(collection, date_key:, precision:, oldest_date:, skip_naps: false)
      Array(collection["records"]).filter_map do |item|
        next unless item["score_state"] == "SCORED"
        next if skip_naps && item["nap"] == true
        date = item[date_key].to_s
        next unless in_date_window?(date, oldest_date)
        value = number(yield(item), precision: precision)
        next if value.nil?
        {"date" => date, "value" => value}
      end.first(7).sort_by { |day| day["date"].to_s }
    end

    def in_date_window?(value, oldest_date)
      Time.parse(value).getlocal.to_date >= oldest_date
    rescue ArgumentError
      false
    end

    def pending_message(score_state, calibrating)
      return "WHOOP is calibrating your baseline" if calibrating
      return "WHOOP is still calculating today's recovery" if score_state == "PENDING_SCORE" || score_state.empty?
      "Today's recovery cannot be scored yet"
    end
  end
end
