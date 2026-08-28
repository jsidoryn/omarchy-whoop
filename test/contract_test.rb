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
    %w[BarWidget.qml Panel.qml Service.qml].each do |file|
      source = File.read(File.join(ROOT, file))
      assert source.include?("io.github.jsidoryn.whoop"), "#{file} must use the manifest id"
    end
  end

  def test_qml_contains_no_literal_hex_colors_or_plaintext_credentials
    Dir.glob(File.join(ROOT, "*.qml")).each do |file|
      source = File.read(file)
      refute source.match?(/#[0-9a-fA-F]{3,8}\b/), "#{File.basename(file)} contains a literal color"
      refute source.match?(/client[_ -]?secret\s*[:=]\s*[\"'][^\"']+/i), "#{File.basename(file)} contains a credential"
    end
  end
end
