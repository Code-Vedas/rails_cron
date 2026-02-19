# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'dispatch_logging'

module RailsCron
  module Lock
    ##
    # Distributed lock adapter using any ActiveRecord-backed SQL database.
    #
    # Despite the "SQLiteAdapter" name, this adapter works with any SQL database
    # supported by Rails (SQLite, PostgreSQL, MySQL, etc.) via ActiveRecord. It stores
    # locks in a database table with TTL-based expiration and uses a UNIQUE constraint
    # on the key column to ensure atomicity.
    #
    # Suitable for single-server or development environments. For production
    # multi-node deployments, use Redis or PostgreSQL adapters instead.
    #
    # @example Using the adapter with any SQL database
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::SQLiteAdapter.new
    #     config.enable_log_dispatch_registry = true  # Enable dispatch logging
    #   end
    class SQLiteAdapter < Adapter
      include DispatchLogging

      ##
      # Initialize a new database-backed adapter.
      #
      # @return [SQLiteAdapter] a new instance
      #   (Note: Despite the class name, this works with any ActiveRecord SQL database)

      ##
      # Get the dispatch registry for database logging.
      #
      # @return [RailsCron::Dispatch::DatabaseEngine] database engine instance
      def dispatch_registry
        @dispatch_registry ||= RailsCron::Dispatch::DatabaseEngine.new
      end

      ##
      # Attempt to acquire a distributed lock in the database.
      #
      # Attempts to insert a new lock record. If the key already exists, cleans up
      # any expired locks and retries once. This avoids unnecessary cleanup in the
      # common case and reduces the window for race conditions.
      #
      # @param key [String] the lock key
      # @param ttl [Integer] time-to-live in seconds
      # @return [Boolean] true if acquired, false if held by another process
      def acquire(key, ttl)
        now = Time.current
        expires_at = now + ttl.seconds

        acquired = begin
          # Try to create a new lock record
          RailsCron::CronLock.create!(
            key: key,
            acquired_at: now,
            expires_at: expires_at
          )
          true
        rescue ActiveRecord::RecordInvalid
          # Key already exists (uniqueness validation failed) or other validation failed.
          # Always clean up any expired locks and retry once in case the existing lock was expired.
          RailsCron::CronLock.cleanup_expired
          begin
            RailsCron::CronLock.create!(
              key: key,
              acquired_at: now,
              expires_at: expires_at
            )
            true
          rescue ActiveRecord::RecordInvalid
            false
          end
        rescue StandardError => e
          raise LockAdapterError, "SQLite acquire failed for #{key}: #{e.message}"
        end

        log_dispatch_attempt(key) if acquired

        acquired
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
  end
end
