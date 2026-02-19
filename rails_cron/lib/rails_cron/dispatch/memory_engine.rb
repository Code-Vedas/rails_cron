# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'registry'

module RailsCron
  module Dispatch
    ##
    # In-memory dispatch registry using a Hash for storage.
    #
    # Stores dispatch records in memory. Suitable for development, testing,
    # or single-node deployments where persistence is not required.
    #
    # @example Usage
    #   registry = RailsCron::Dispatch::MemoryEngine.new
    #   registry.log_dispatch('daily_report', Time.current, 'node-1')
    #   registry.dispatched?('daily_report', Time.current) # => true
    class MemoryEngine < Registry
      ##
      # Initialize a new in-memory registry.
      def initialize
        super
        @dispatches = {}
        @mutex = Mutex.new
      end

      ##
      # Log a dispatch attempt in memory.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @param node_id [String] identifier for the dispatching node
      # @param status [String] dispatch status ('dispatched', 'failed', etc.)
      # @return [Hash] the stored dispatch record
      def log_dispatch(key, fire_time, node_id, status = 'dispatched')
        @mutex.synchronize do
          storage_key = build_key(key, fire_time)
          @dispatches[storage_key] = {
            key: key,
            fire_time: fire_time,
            dispatched_at: Time.current,
            node_id: node_id,
            status: status
          }
        end
      end

      ##
      # Find a dispatch record for a specific job and fire time.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @return [Hash, nil] dispatch record or nil if not found
      def find_dispatch(key, fire_time)
        @mutex.synchronize do
          storage_key = build_key(key, fire_time)
          @dispatches[storage_key]
        end
      end

      ##
      # Clear all stored dispatch records.
      # Useful for testing.
      #
      # @return [void]
      def clear
        @mutex.synchronize do
          @dispatches.clear
        end
      end

      ##
      # Get the number of stored dispatch records.
      #
      # @return [Integer] number of dispatch records
      def size
        @mutex.synchronize do
          @dispatches.size
        end
      end

      private

      ##
      # Build a storage key from job key and fire time.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] the fire time
      # @return [String] storage key
      def build_key(key, fire_time)
        "#{key}:#{fire_time.to_i}"
      end
    end
  end
end
