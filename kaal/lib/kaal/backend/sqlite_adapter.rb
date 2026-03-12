# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'dispatch_logging'
require_relative '../definition/database_engine'

module Kaal
  module Backend
    ##
    # Distributed backend adapter using any ActiveRecord-backed SQL database.
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
    #   Kaal.configure do |config|
    #     config.backend = Kaal::Backend::SQLiteAdapter.new
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
      # @return [Kaal::Dispatch::DatabaseEngine] database engine instance
      def dispatch_registry
        @dispatch_registry ||= Kaal::Dispatch::DatabaseEngine.new
      end

      ##
      # Get the definition registry for database-backed definition persistence.
      #
      # @return [Kaal::Definition::DatabaseEngine] database definition engine instance
      def definition_registry
        @definition_registry ||= Kaal::Definition::DatabaseEngine.new
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
        acquired = false
        attempt_cleanup = false

        2.times do
          Kaal::CronLock.cleanup_expired if attempt_cleanup
          begin
            Kaal::CronLock.create!(
              key: key,
              acquired_at: now,
              expires_at: expires_at
            )
            acquired = true
            break
          rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
            attempt_cleanup = true
          rescue ActiveRecord::StatementInvalid => e
            raise unless wrapped_contention_error?(e)

            attempt_cleanup = true
          end
        end

        log_dispatch_attempt(key) if acquired

        acquired
      rescue StandardError => e
        raise LockAdapterError, "SQLite acquire failed for #{key}: #{e.message}"
      end

      ##
      # Release a previously acquired lock.
      #
      # @param key [String] the lock key to release
      # @return [Boolean] true if released (key existed and was deleted), false if not held
      def release(key)
        deleted = Kaal::CronLock.where(key: key).delete_all
        deleted.positive?
      rescue StandardError => e
        raise LockAdapterError, "SQLite release failed for #{key}: #{e.message}"
      end

      private

      def wrapped_contention_error?(error)
        cause = error.cause
        cause.is_a?(ActiveRecord::RecordNotUnique) || error.message.match?(/unique|duplicate/i)
      end
    end
  end
end
