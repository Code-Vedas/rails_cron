# frozen_string_literal: true

module RailsCron
  # Raised when scheduler file configuration is invalid or cannot be loaded.
  class SchedulerConfigError < StandardError; end
end
