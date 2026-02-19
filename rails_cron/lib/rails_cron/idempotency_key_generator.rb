# frozen_string_literal: true

module RailsCron
  ##
  # Utility class for generating idempotency keys.
  #
  # Centralizes the key format to prevent drift between public API and internal coordinator.
  # Format: {namespace}-{cron_key}-{fire_time_unix}
  #
  # @example Generate a key
  #   key = RailsCron::IdempotencyKeyGenerator.call('reports:daily', Time.current, configuration: config)
  #   # => "railscron-reports:daily-1708283400"
  class IdempotencyKeyGenerator
    ##
    # Generate an idempotency key for a cron job.
    #
    # @param cron_key [String] the cron job key
    # @param fire_time [Time] the fire time
    # @param configuration [Configuration] the RailsCron configuration instance
    # @return [String] the formatted idempotency key
    def self.call(cron_key, fire_time, configuration:)
      namespace = configuration.namespace || 'railscron'
      "#{namespace}-#{cron_key}-#{fire_time.to_i}"
    end
  end
end
