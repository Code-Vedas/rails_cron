# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'socket'

module RailsCron
  module Lock
    ##
    # Shared module for dispatch logging across lock adapters.
    #
    # Provides methods to log cron job dispatch attempts to the CronDispatch model
    # for audit and observability purposes. Adapters that support dispatch logging
    # should include this module.
    module DispatchLogging
      ##
      # Log a dispatch attempt to the CronDispatch model.
      #
      # @param key [String] the lock key (format: "namespace:dispatch:cron_key:fire_time")
      # @raise [LockAdapterError] if dispatch logging fails
      def log_dispatch_attempt(key)
        cron_key, fire_time = parse_lock_key(key)
        node_id = Socket.gethostname

        ::RailsCron::CronDispatch.create!(
          key: cron_key,
          fire_time: fire_time,
          dispatched_at: Time.current,
          node_id: node_id,
          status: 'dispatched'
        )
      rescue StandardError => e
        raise LockAdapterError, "Failed to log dispatch for #{key}: #{e.message}"
      end

      ##
      # Parse a lock key to extract cron job key and fire time.
      #
      # Lock key format: "namespace:dispatch:cron_key:fire_time"
      # Parses by splitting on colon: removes namespace and "dispatch", then
      # rejoins remaining parts as the cron key.
      #
      # @param key [String] the lock key to parse
      # @return [Array<String, Time>] tuple of [cron_key, fire_time]
      def parse_lock_key(key)
        parts = key.split(':')
        fire_time_unix = parts.pop.to_i
        2.times { parts.shift } # Remove namespace and "dispatch"
        cron_key = parts.join(':')
        fire_time = Time.at(fire_time_unix)

        [cron_key, fire_time]
      end
    end
  end
end
