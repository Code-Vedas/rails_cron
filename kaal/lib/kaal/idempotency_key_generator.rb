# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  ##
  # Utility class for generating idempotency keys.
  #
  # Centralizes the key format to prevent drift between public API and internal coordinator.
  # Format: {namespace}-{cron_key}-{fire_time_unix}
  #
  # @example Generate a key
  #   key = Kaal::IdempotencyKeyGenerator.call('reports:daily', Time.current, configuration: config)
  #   # => "kaal-reports:daily-1708283400"
  class IdempotencyKeyGenerator
    ##
    # Generate an idempotency key for a cron job.
    #
    # @param cron_key [String] the cron job key
    # @param fire_time [Time] the fire time
    # @param configuration [Configuration] the Kaal configuration instance
    # @return [String] the formatted idempotency key
    def self.call(cron_key, fire_time, configuration:)
      namespace = configuration.namespace || 'kaal'
      "#{namespace}-#{cron_key}-#{fire_time.to_i}"
    end
  end
end
