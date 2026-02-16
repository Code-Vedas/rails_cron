# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  module Lock
    ##
    # Abstract base class for distributed lock adapters.
    #
    # Lock adapters are responsible for acquiring and releasing distributed locks
    # to ensure that each scheduled cron job runs exactly once across multiple nodes.
    #
    # @example Implementing a lock adapter
    #   class MyLockAdapter < RailsCron::Lock::Adapter
    #     def acquire(key, ttl)
    #       # Try to acquire a lock with key and TTL
    #       # Return true if acquired, false otherwise
    #     end
    #
    #     def release(key)
    #       # Release the lock for key
    #     end
    #   end
    class Adapter
      ##
      # Attempt to acquire a distributed lock.
      #
      # @param key [String] the lock key (e.g., "namespace:cron:key:timestamp")
      # @param ttl [Integer] time-to-live in seconds before the lock auto-expires
      # @return [Boolean] true if lock was acquired, false if already held by another process
      #
      # @raise [NotImplementedError] if not implemented by subclass
      #
      # @example
      #   adapter = MyLockAdapter.new
      #   acquired = adapter.acquire("railscron:job1:1234567890", 60)
      #   if acquired
      #     # Do work...
      #   end
      def acquire(_key, _ttl)
        raise NotImplementedError, 'Subclasses must implement #acquire'
      end

      ##
      # Release a previously acquired lock.
      #
      # @param key [String] the lock key to release
      # @return [Boolean] true if released, false if not held
      #
      # @raise [NotImplementedError] if not implemented by subclass
      #
      # @example
      #   adapter.release("railscron:job1:1234567890")
      def release(_key)
        raise NotImplementedError, 'Subclasses must implement #release'
      end
    end

    ##
    # Null adapter that always succeeds (useful for development/testing).
    #
    # This adapter provides a no-op implementation: it always returns true
    # for acquire and does nothing on release. Use this when you want to run
    # the scheduler without distributed locking (e.g., single-node development).
    #
    # @example Using the null adapter
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::NullAdapter.new
    #   end
    class NullAdapter < Adapter
      ##
      # Always returns true (lock always "acquired").
      #
      # @param _key [String] unused
      # @param _ttl [Integer] unused
      # @return [Boolean] always true
      def acquire(_key, _ttl) # rubocop:disable Naming/PredicateMethod
        true
      end

      ##
      # No-op implementation (nothing to release).
      #
      # @param _key [String] unused
      # @return [Boolean] always true
      def release(_key) # rubocop:disable Naming/PredicateMethod
        true
      end
    end
  end
end
