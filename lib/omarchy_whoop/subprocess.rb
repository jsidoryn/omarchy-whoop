# frozen_string_literal: true

module OmarchyWhoop
  # Shared shape for the desktop and keyring commands the helper shells out to.
  module Subprocess
    Result = Struct.new(:stdout, :stderr, :success?)

    # Reduce a command's stderr to one bounded line suitable for a user-facing error.
    def self.concise(value, fallback)
      line = value.to_s.lines.map(&:strip).find { |item| !item.empty? }
      line.nil? ? fallback : "#{fallback}: #{line[0, 180]}"
    end
  end
end
