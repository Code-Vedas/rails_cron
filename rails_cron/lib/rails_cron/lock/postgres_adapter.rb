# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'digest'
require 'socket'
require_relative 'dispatch_logging'

module RailsCron
  module Lock
    ##
    # Distributed lock adapter using PostgreSQL advisory locks.
    #
    # This adapter uses PostgreSQL's pg_try_advisory_lock function for
    # distributed locking across multiple nodes. Locks are connection-based
    # and automatically released when the database connection is closed.
    #
    # **IMPORTANT LIMITATIONS:**
    # - The +ttl+ parameter is ignored. Locks do not auto-expire based on time;
    #   they persist until the database connection terminates.
    # - If a process crashes while holding a lock, the lock will remain held until
    #   the connection timeout occurs (typically 30-60 minutes). For critical systems,
    #   consider monitoring stale locks or using a time-based fallback mechanism.
    # - Ensure connection pooling is properly configured to release connections
    #   promptly when processes terminate.
    #
    # Optionally logs all dispatch attempts to the CronDispatch model for
    # audit/observability purposes.
    #
    # @example Using the PostgreSQL adapter
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::PostgresAdapter.new
    #   end
    #
    # @example With audit logging
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::PostgresAdapter.new(log_dispatch: true)
    #   end
    class PostgresAdapter < Adapter
      include DispatchLogging

      attr_reader :log_dispatch

      ##
      # Initialize a new PostgreSQL adapter.
      #
      # @param log_dispatch [Boolean] whether to log dispatch attempts to CronDispatch model (default: false)
      def initialize(log_dispatch: false)
        super()
        @log_dispatch = log_dispatch
      end

      ##
      # Attempt to acquire a distributed lock using PostgreSQL advisory lock.
      #
      # Converts the lock key to a deterministic 64-bit integer hash and attempts
      # to acquire the advisory lock. If successful, records the dispatch attempt
      # if log_dispatch is enabled.
      #
      # **Note:** The +ttl+ parameter is ignored. PostgreSQL advisory locks are
      # connection-based and do not auto-expire. The lock will be held until the
      # database connection is closed. See class documentation for limitations.
      #
      # @param key [String] the lock key (format: "namespace:dispatch:cron_key:fire_time")
      # @param ttl [Integer] time-to-live in seconds (ignored; see class docs)
      # @return [Boolean] true if acquired, false if held by another process
      def acquire(key, _ttl)
        lock_id = calculate_lock_id(key)

        sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_try_advisory_lock(?)', lock_id])
        acquired = cast_to_boolean(ActiveRecord::Base.connection.execute(sql).first['pg_try_advisory_lock'])

        log_dispatch_attempt(key) if acquired && @log_dispatch

        acquired
      rescue StandardError => e
        raise LockAdapterError, "PostgreSQL acquire failed for #{key}: #{e.message}"
      end

      ##
      # Release a distributed lock held by PostgreSQL advisory lock.
      #
      # @param key [String] the lock key
      # @return [Boolean] true if released, false if not held
      def release(key)
        lock_id = calculate_lock_id(key)

        sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_unlock(?)', lock_id])
        cast_to_boolean(ActiveRecord::Base.connection.execute(sql).first['pg_advisory_unlock'])
      rescue StandardError => e
        raise LockAdapterError, "PostgreSQL release failed for #{key}: #{e.message}"
      end

      private

      def cast_to_boolean(value)
        # PostgreSQL's `.execute` returns "t"/"f" strings for boolean columns,
        # not Ruby true/false. Explicitly cast to boolean for proper semantics.
        case value
        when 't'
          true
        when 'f'
          false
        when true, false
          value
        else
          !value.to_s.match?(/\A(f|false|0|)\z/i)
        end
      end

      def calculate_lock_id(key)
        # Use MD5 hash of the key and convert to 64-bit signed integer
        # Ensure it's in the range of a signed 64-bit integer
        hash = Digest::MD5.digest(key).unpack1('Q>')
        # Convert to signed 64-bit integer
        hash > 9_223_372_036_854_775_807 ? hash - 18_446_744_073_709_551_616 : hash
      end
    end
  end
end
