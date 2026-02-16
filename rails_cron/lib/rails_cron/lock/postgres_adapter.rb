# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'digest'
require 'socket'

module RailsCron
  module Lock
    ##
    # Distributed lock adapter using PostgreSQL advisory locks.
    #
    # This adapter uses PostgreSQL's pg_try_advisory_lock function for
    # distributed locking across multiple nodes. The lock is automatically
    # released when the database connection is closed.
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
      # @param key [String] the lock key (format: "namespace:dispatch:cron_key:fire_time")
      # @param ttl [Integer] time-to-live in seconds (note: PG advisory locks don't auto-expire)
      # @return [Boolean] true if acquired, false if held by another process
      def acquire(key, _ttl)
        lock_id = calculate_lock_id(key)

        acquired = ActiveRecord::Base.connection.execute(
          "SELECT pg_try_advisory_lock(#{lock_id})"
        ).first['pg_try_advisory_lock']

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

        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_unlock(#{lock_id})"
        ).first['pg_advisory_unlock']
      rescue StandardError => e
        raise LockAdapterError, "PostgreSQL release failed for #{key}: #{e.message}"
      end

      private

      def calculate_lock_id(key)
        # Use MD5 hash of the key and convert to 64-bit signed integer
        # Ensure it's in the range of a signed 64-bit integer
        hash = Digest::MD5.digest(key).unpack1('Q>')
        # Convert to signed 64-bit integer
        hash > 9_223_372_036_854_775_807 ? hash - 18_446_744_073_709_551_616 : hash
      end

      def log_dispatch_attempt(key)
        cron_key, fire_time = parse_lock_key(key)
        node_id = Socket.gethostname

        ::RailsCron::CronDispatch.create!(
          key: cron_key,
          fire_time: fire_time,
          dispatched_at: Time.current,
          node_id: node_id,
          status: 'dispatched'
        )
      rescue StandardError => e
        raise LockAdapterError, "Failed to log dispatch for #{key}: #{e.message}"
      end

      def parse_lock_key(key)
        # Lock key format: "namespace:dispatch:cron_key:fire_time"
        # Parse by splitting on colon: remove namespace, "dispatch", then rejoin remaining parts as key
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
