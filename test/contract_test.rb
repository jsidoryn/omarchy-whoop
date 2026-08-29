# frozen_string_literal: true

require_relative "test_helper"

class ContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_manifest_declares_a_shared_service_and_bar_widget
    manifest = JSON.parse(File.read(File.join(ROOT, "manifest.json")))

    assert_equal 1, manifest.fetch("schemaVersion")
    assert_equal "io.github.jsidoryn.whoop", manifest.fetch("id")
    assert_equal %w[service bar-widget], manifest.fetch("kinds")
    assert_equal "Service.qml", manifest.dig("entryPoints", "service")
    assert_equal "BarWidget.qml", manifest.dig("entryPoints", "barWidget")
    assert_equal "right", manifest.dig("barWidget", "defaultSection")
  end

  def test_ui_uses_the_same_stable_plugin_id
    %w[Service.qml BarWidget.qml Panel.qml].each do |file|
      source = File.read(File.join(ROOT, file))
      assert source.include?("io.github.jsidoryn.whoop"), "#{file} must use the manifest id"
    end
  end

  def test_ipc_is_owned_by_the_single_shared_service
    service = File.read(File.join(ROOT, "Service.qml"))
    panel = File.read(File.join(ROOT, "Panel.qml"))

    assert service.include?("IpcHandler {")
    refute panel.include?("IpcHandler {")
  end

  def test_panel_presents_the_three_whoop_scores_without_interpretation
    panel = File.read(File.join(ROOT, "Panel.qml"))

    bindings = {
      "Recovery" => %(Model.metric(root.recovery.score, "%")),
      "Sleep" => %(Model.metric(root.sleep.performance, "%")),
      "Strain" => %(Model.metric(root.cycle.strain, "", 1))
    }

    bindings.each do |score, binding|
      assert panel.include?(%(label: "#{score}")), "Panel must show the #{score} score directly"
      assert panel.include?(%(value: #{binding})), "#{score} must use its direct WHOOP field"
    end
    refute panel.match?(/recoveryBand|\.band\./)
  end

  def test_panel_explains_unscored_live_recovery_without_interpreting_it
    panel = File.read(File.join(ROOT, "Panel.qml"))

    assert panel.include?(%(root.snapshotData.state === "pending"))
    assert panel.include?(%(String(root.snapshotData.message || "")))
  end

  def test_recovery_metric_tiles_are_equal_height_and_trends_are_cycleable
    panel = File.read(File.join(ROOT, "Panel.qml"))

    refute panel.include?(%(detail: "RMSSD"))
    assert panel.include?(%(property string trendMetric: "recovery"))
    assert panel.include?(%(id: trendButton))
    assert panel.include?(%(Model.nextTrend(root.trendMetric)))
    assert panel.include?(%(Model.trendValues(root.snapshotData, root.trendMetric)))
    assert panel.include?(%(Model.trendEmptyMessage(root.snapshotData, root.trendMetric)))
    assert panel.include?(%(onClicked: root.cycleTrend()))
    assert panel.include?(%(text === "t" || text === "T"))
  end

  def test_qml_contains_no_literal_hex_colors_or_plaintext_credentials
    Dir.glob(File.join(ROOT, "*.qml")).each do |file|
      source = File.read(file)
      refute source.match?(/#[0-9a-fA-F]{3,8}\b/), "#{File.basename(file)} contains a literal color"
      refute source.match?(/client[_ -]?secret\s*[:=]\s*[\"'][^\"']+/i), "#{File.basename(file)} contains a credential"
    end
  end
end
