# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'socket'

module Kaal
  module Backend
    ##
    # Shared module for dispatch logging across backend adapters.
    #
    # Provides methods to log cron job dispatch attempts via the dispatch registry
    # for audit and observability purposes. Adapters that support dispatch logging
    # should include this module and implement a dispatch_registry method.
    #
    # @example Implementing in an adapter
    #   class MyAdapter < Adapter
    #     include DispatchLogging
    #
    #     def dispatch_registry
    #       @dispatch_registry ||= Kaal::Dispatch::MemoryEngine.new
    #     end
    #   end
    module DispatchLogging
      ##
      # Log a dispatch attempt via the dispatch registry.
      #
      # Only logs if Kaal.configuration.enable_log_dispatch_registry is true.
      #
      # @param key [String] the lock key (format: "namespace:dispatch:cron_key:fire_time")
      # @return [void]
      def log_dispatch_attempt(key)
        logger = nil
        logging_enabled = Kaal.configuration.then do |configuration|
          logger = configuration.logger
          configuration.enable_log_dispatch_registry
        end
        return unless logging_enabled
        return unless respond_to?(:dispatch_registry)

        registry = dispatch_registry
        return unless registry

        cron_key, fire_time = parse_lock_key(key)
        node_id = Socket.gethostname

        registry.log_dispatch(cron_key, fire_time, node_id, 'dispatched')
      rescue StandardError => e
        logger&.error("Failed to log dispatch for #{key}: #{e.message}")
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
        DispatchLogging.parse_lock_key(key)
      end

      def self.parse_lock_key(key)
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
