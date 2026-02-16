# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  module Lock
    ##
    # Distributed lock adapter using SQLite (or any SQL database via ActiveRecord).
    #
    # This adapter stores locks in a database table with TTL-based expiration.
    # Uses UNIQUE constraint on the key column to ensure atomicity.
    #
    # Suitable for single-server or development environments. For production
    # multi-node deployments, use Redis or PostgreSQL adapters instead.
    #
    # @example Using the SQLite adapter
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::SQLiteAdapter.new
    #   end
    class SQLiteAdapter < Adapter
      ##
      # Initialize a new SQLite adapter.
      #
      # @return [SQLiteAdapter] a new instance

      ##
      # Attempt to acquire a distributed lock in the database.
      #
      # Cleans up any expired locks first, then attempts to insert a new lock.
      # Returns true if insert succeeds, false if key already exists.
      #
      # @param key [String] the lock key
      # @param ttl [Integer] time-to-live in seconds
      # @return [Boolean] true if acquired, false if held by another process
      def acquire(key, ttl)
        now = Time.current
        expires_at = now + ttl.seconds

        begin
          # Clean up any expired locks first
          RailsCron::CronLock.cleanup_expired

          # Try to create a new lock record
          RailsCron::CronLock.create!(
            key: key,
            acquired_at: now,
            expires_at: expires_at
          )
          true
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          # Key already exists - another process holds the lock
          false
        rescue StandardError => e
          raise LockAdapterError, "SQLite acquire failed for #{key}: #{e.message}"
        end
      end

      ##
      # Release a previously acquired lock.
      #
      # @param key [String] the lock key to release
      # @return [Boolean] true if released (key existed and was deleted), false if not held
      def release(key)
        deleted = RailsCron::CronLock.where(key: key).delete_all
        deleted.positive?
      rescue StandardError => e
        raise LockAdapterError, "SQLite release failed for #{key}: #{e.message}"
      end
    end

    ##
    # Error raised when a lock adapter operation fails.
    class LockAdapterError < StandardError; end
  end
end
