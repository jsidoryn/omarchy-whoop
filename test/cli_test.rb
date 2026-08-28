# frozen_string_literal: true

require "stringio"
require_relative "test_helper"

class CliTest < Minitest::Test
  EmptyStore = Struct.new(:unused) do
    def read = nil
  end

  def test_snapshot_preserves_the_requested_fallback_demo
    output = StringIO.new
    status = OmarchyWhoop::Cli.new(
      %w[snapshot --fallback-demo strained],
      output: output,
      error: StringIO.new,
      store: EmptyStore.new
    ).run

    result = JSON.parse(output.string)
    assert_equal 0, status
    assert_equal "demo", result.fetch("mode")
    assert_equal "strained", result.fetch("demoScenario")
    assert_match(/Connect WHOOP/, result.fetch("message"))
  end

  def test_snapshot_defaults_to_the_primed_demo_without_credentials
    output = StringIO.new
    OmarchyWhoop::Cli.new(
      ["snapshot"],
      output: output,
      error: StringIO.new,
      store: EmptyStore.new
    ).run

    assert_equal "primed", JSON.parse(output.string).fetch("demoScenario")
  end
end
