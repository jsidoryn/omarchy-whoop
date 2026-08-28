# frozen_string_literal: true

require "time"

module OmarchyWhoop
  module Demo
    module_function

    SCENARIOS = {
      "primed" => {score: 88, strain: 8.4, sleep: 93, hrv: 72.8, rhr: 46, label: "Primed for a strong day", history: [62, 71, 55, 78, 69, 84, 88]},
      "balanced" => {score: 64, strain: 12.7, sleep: 82, hrv: 56.1, rhr: 51, label: "Balanced — train with intent", history: [74, 68, 81, 58, 72, 70, 64]},
      "strained" => {score: 29, strain: 17.2, sleep: 61, hrv: 34.7, rhr: 61, label: "Recovery day recommended", history: [79, 67, 54, 48, 41, 36, 29]},
      "pending" => {score: nil, strain: 3.1, sleep: nil, hrv: nil, rhr: nil, label: "WHOOP is calculating recovery", history: [72, 81, 66, 58, 77, 69, 74]}
    }.freeze

    def snapshot(name = "primed", now: Time.now.utc, connected: false)
      scenario = SCENARIOS.key?(name.to_s) ? name.to_s : "primed"
      data = SCENARIOS.fetch(scenario)
      pending = data[:score].nil?
      {
        "schemaVersion" => 1,
        "state" => pending ? "pending" : "demo",
        "mode" => "demo",
        "connected" => connected,
        "message" => data[:label],
        "fetchedAt" => now.iso8601,
        "demoScenario" => scenario,
        "recovery" => {
          "score" => data[:score], "scoreState" => pending ? "PENDING_SCORE" : "SCORED", "calibrating" => false,
          "hrvMs" => data[:hrv], "restingHeartRate" => data[:rhr], "spo2" => pending ? nil : 97.4, "skinTempC" => pending ? nil : 33.4
        },
        "cycle" => {"id" => 9001, "start" => (now - 8 * 3600).iso8601, "strain" => data[:strain], "kilojoule" => 6_820, "averageHeartRate" => 69, "maxHeartRate" => 164},
        "sleep" => {
          "scoreState" => pending ? "PENDING_SCORE" : "SCORED", "performance" => data[:sleep], "consistency" => pending ? nil : 86,
          "efficiency" => pending ? nil : 92.4, "actualHours" => pending ? nil : 7.42, "neededHours" => 8.05,
          "disturbances" => pending ? nil : 9, "lightHours" => pending ? nil : 3.62, "slowWaveHours" => pending ? nil : 1.61, "remHours" => pending ? nil : 2.19
        },
        "week" => data[:history].each_with_index.map { |score, index| {"date" => (now - (6 - index) * 86_400).iso8601, "score" => score} }
      }
    end
  end
end
