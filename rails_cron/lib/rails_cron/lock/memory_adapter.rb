# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

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
    #   end
    class MemoryAdapter < Adapter
      def initialize
        super
        @locks = {}
        @mutex = Mutex.new
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
        @mutex.synchronize do
          prune_expired_locks
          expiration_time = @locks[key]
          current_time = Time.current
          return false if expiration_time && expiration_time > current_time

          @locks[key] = current_time + ttl.seconds
          true
        end
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
