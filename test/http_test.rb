# frozen_string_literal: true

require_relative "test_helper"

class HttpTest < Minitest::Test
  def test_wraps_tls_failures_in_the_plugin_error_contract
    with_net_http_failure(OpenSSL::SSL::SSLError.new("certificate verify failed")) do
      error = assert_raises(OmarchyWhoop::HttpError) do
        OmarchyWhoop::Http.new.request(:get, "https://api.prod.whoop.com/developer/v2/cycle")
      end

      assert_equal 0, error.status
      assert_match(/certificate verify failed/, error.message)
    end
  end

  def test_wraps_unexpected_eof_in_the_plugin_error_contract
    with_net_http_failure(EOFError.new("end of file reached")) do
      error = assert_raises(OmarchyWhoop::HttpError) do
        OmarchyWhoop::Http.new.request(:get, "https://api.prod.whoop.com/developer/v2/cycle")
      end

      assert_equal 0, error.status
      assert_match(/end of file reached/, error.message)
    end
  end

  private

  def with_net_http_failure(error)
    singleton = Net::HTTP.singleton_class
    original = Net::HTTP.method(:start)
    singleton.define_method(:start) { |*_args, **_kwargs, &_block| raise error }
    yield
  ensure
    singleton.define_method(:start, original)
  end
end
