# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'dispatch_logging'

module RailsCron
  module Lock
    ##
    # In-memory lock adapter using Mutex and Hash.
    #
    # This adapter stores locks in memory with TTL tracking. Locks are stored
    # with an expiration time and automatically considered released if the TTL
    # has passed.
    #
    # **IMPORTANT**: This adapter is suitable only for single-node deployments
    # (development, testing). For multi-node production systems, use Redis or
    # PostgreSQL adapters instead.
    #
    # @example Using the memory adapter
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::MemoryAdapter.new
    #     config.enable_log_dispatch_registry = true  # Enable dispatch logging
    #   end
    class MemoryAdapter < Adapter
      include DispatchLogging

      def initialize
        super
        @locks = {}
        @mutex = Mutex.new
      end

      ##
      # Get the dispatch registry for in-memory logging.
      #
      # @return [RailsCron::Dispatch::MemoryEngine] memory engine instance
      def dispatch_registry
        @dispatch_registry ||= RailsCron::Dispatch::MemoryEngine.new
      end

      ##
      # Attempt to acquire a lock in memory.
      #
      # Opportunistically prunes expired locks to prevent unbounded memory growth.
      # Since the coordinator generates unique keys per dispatch and relies on TTL
      # expiration without calling release, this pruning is essential.
      #
      # @param key [String] the lock key
      # @param ttl [Integer] time-to-live in seconds
      # @return [Boolean] true if acquired (key was free or expired), false if held by another process
      def acquire(key, ttl)
        acquired = @mutex.synchronize do
          prune_expired_locks
          expiration_time = @locks[key]
          current_time = Time.current
          next false if expiration_time && expiration_time > current_time

          @locks[key] = current_time + ttl.seconds
          true
        end

        log_dispatch_attempt(key) if acquired

        acquired
      end

      ##
      # Release a lock from memory.
      #
      # @param key [String] the lock key to release
      # @return [Boolean] true if released (key was held), false if not held
      def release(key)
        @mutex.synchronize do
          @locks.delete(key).present?
        end
      end

      private

      def prune_expired_locks
        now = Time.current
        @locks.delete_if { |_key, expiration_time| expiration_time <= now }
      end
    end
  end
end
