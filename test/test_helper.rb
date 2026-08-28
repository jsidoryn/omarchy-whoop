# frozen_string_literal: true

require "json"
require "tmpdir"

# Tiny zero-dependency test harness. Omarchy ships Ruby but not its optional
# test gems, so the project tests deliberately run on the same stock runtime
# as the plugin.
module Minitest
  class Assertion < StandardError; end

  class Test
    @test_classes = []

    class << self
      attr_reader :test_classes

      def inherited(child)
        Test.test_classes << child
      end
    end

    def assert(value, message = "expected a truthy value")
      raise Assertion, message unless value
    end

    def refute(value, message = "expected a falsey value") = assert(!value, message)
    def assert_equal(expected, actual, message = nil) = assert(expected == actual, message || "expected #{expected.inspect}, got #{actual.inspect}")
    def assert_nil(actual, message = nil) = assert_equal(nil, actual, message)
    def assert_match(pattern, actual, message = nil) = assert(pattern.match?(actual.to_s), message || "expected #{actual.inspect} to match #{pattern.inspect}")
    def assert_in_delta(expected, actual, delta, message = nil) = assert((expected - actual).abs <= delta, message || "expected #{actual} within #{delta} of #{expected}")

    def assert_raises(error_class)
      yield
    rescue error_class => error
      return error
    rescue StandardError => error
      raise Assertion, "expected #{error_class}, got #{error.class}: #{error.message}"
    else
      raise Assertion, "expected #{error_class} to be raised"
    end
  end
end

at_exit do
  failures = []
  count = 0
  Minitest::Test.test_classes.each do |test_class|
    test_class.instance_methods(false).grep(/^test_/).sort.each do |method|
      count += 1
      test_class.new.public_send(method)
      $stdout.print "."
    rescue StandardError => error
      $stdout.print "F"
      failures << ["#{test_class}##{method}", error]
    end
  end
  puts "\n#{count} tests, #{failures.length} failures"
  failures.each do |name, error|
    warn "\n#{name}: #{error.class}: #{error.message}"
    warn error.backtrace.first(5).join("\n")
  end
  exit 1 unless failures.empty?
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "omarchy_whoop"
