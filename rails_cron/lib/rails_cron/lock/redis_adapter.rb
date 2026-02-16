# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module RailsCron
  module Lock
    ##
    # Distributed lock adapter using Redis.
    #
    # This adapter uses Redis SET command with NX (only set if not exists) and
    # PX (expire in milliseconds) options to implement atomic lock acquisition
    # with automatic TTL-based expiration.
    #
    # The lock value is a unique identifier (UUID) to allow safe release by
    # preventing deletion of locks acquired by other processes.
    #
    # @example Using the Redis adapter
    #   redis = Redis.new(url: ENV["REDIS_URL"])
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::RedisAdapter.new(redis)
    #   end
    class RedisAdapter < Adapter
      ##
      # Initialize a new Redis adapter.
      #
      # @param redis [Object] a Redis-compatible client instance
      # @raise [ArgumentError] if redis is not provided or does not implement the required interface
      def initialize(redis)
        super()
        raise ArgumentError, 'redis client is required' if redis.nil?
        raise ArgumentError, 'redis client must respond to :set and :eval' unless redis.respond_to?(:set) && redis.respond_to?(:eval)

        @redis = redis
        @lock_values = {}
        @mutex = Mutex.new
      end

      ##
      # Attempt to acquire a distributed lock in Redis.
      #
      # Uses SET key value NX PX ttl to atomically acquire the lock with TTL.
      # Stores the lock value locally to enable safe release.
      #
      # @param key [String] the lock key
      # @param ttl [Integer] time-to-live in seconds
      # @return [Boolean] true if acquired, false if held by another process
      def acquire(key, ttl)
        lock_value = generate_lock_value
        ttl_ms = ttl * 1000

        # SET key value NX PX ttl returns OK if set, nil if not set
        result = @redis.set(key, lock_value, nx: true, px: ttl_ms)

        if result
          @mutex.synchronize do
            @lock_values[key] = lock_value
          end
        end

        result.present?
      rescue StandardError => e
        raise LockAdapterError, "Redis acquire failed for #{key}: #{e.message}"
      end

      ##
      # Release a distributed lock from Redis.
      #
      # Safely deletes the lock only if the stored value matches the value
      # we set during acquire. This prevents releasing locks acquired by other processes.
      #
      # @param key [String] the lock key to release
      # @return [Boolean] true if released (key was held with our value), false otherwise
      def release(key)
        lock_value = @mutex.synchronize do
          @lock_values.delete(key)
        end

        return false unless lock_value

        # Use a Lua script to delete only if value matches
        script = <<~LUA
          if redis.call('get', KEYS[1]) == ARGV[1] then
            return redis.call('del', KEYS[1])
          else
            return 0
          end
        LUA

        result = @redis.eval(script, keys: [key], argv: [lock_value])
        result.present? && result.positive?
      rescue StandardError => e
        raise LockAdapterError, "Redis release failed for #{key}: #{e.message}"
      end

      private

      def generate_lock_value
        SecureRandom.uuid
      end
    end
  end
end
