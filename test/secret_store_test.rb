# frozen_string_literal: true

require_relative "test_helper"

class SecretStoreTest < Minitest::Test
  Result = Struct.new(:stdout, :stderr, :success?)

  def test_reads_one_json_bundle_with_exact_attributes
    calls = []
    runner = lambda do |argv, stdin_data: nil|
      calls << [argv, stdin_data]
      Result.new(%({"refresh_token":"rotating"}\n), "", true)
    end

    bundle = OmarchyWhoop::SecretStore.new(runner: runner).read

    assert_equal "rotating", bundle.fetch("refresh_token")
    assert_equal [["secret-tool", "lookup", "service", "omarchy-whoop", "account", "credentials"]], calls.map(&:first)
  end

  def test_writes_the_complete_bundle_through_stdin
    calls = []
    runner = lambda do |argv, stdin_data: nil|
      calls << [argv, stdin_data]
      Result.new("", "", true)
    end
    bundle = {"client_id" => "id", "client_secret" => "secret", "refresh_token" => "next"}

    OmarchyWhoop::SecretStore.new(runner: runner).write(bundle)

    argv, stdin_data = calls.fetch(0)
    assert_equal ["secret-tool", "store", "--label=Omarchy WHOOP credentials", "service", "omarchy-whoop", "account", "credentials"], argv
    assert_equal bundle, JSON.parse(stdin_data)
  end

  def test_never_uses_secret_tool_search
    calls = []
    runner = lambda do |argv, stdin_data: nil|
      calls << argv
      Result.new("", "", false)
    end

    assert_nil OmarchyWhoop::SecretStore.new(runner: runner).read
    refute calls.flatten.include?("search")
  end
end

