# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'socket'

module RailsCron
  module Lock
    ##
    # Distributed lock adapter using MySQL named locks (GET_LOCK/RELEASE_LOCK).
    #
    # This adapter uses MySQL's GET_LOCK and RELEASE_LOCK functions for
    # distributed locking across multiple nodes. Locks are connection-based
    # and automatically released when the database connection is closed.
    #
    # **IMPORTANT LIMITATIONS:**
    # - Locks are connection-scoped: if a process crashes, the lock persists until
    #   the database connection timeout occurs (typically 28,800 seconds or 8 hours).
    #   For critical systems, consider monitoring stale locks or using a time-based
    #   fallback mechanism.
    # - MySQL named locks can only be up to 64 characters. Lock keys longer than
    #   64 characters are truncated (with warning), potentially causing collisions.
    # - GET_LOCK has a configurable timeout (default 5 seconds via net_read_timeout).
    # - Ensure connection pooling is properly configured to release connections
    #   promptly when processes terminate.
    #
    # Optionally logs all dispatch attempts to the CronDispatch model for
    # audit/observability purposes.
    #
    # @example Using the MySQL adapter
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::MySQLAdapter.new
    #   end
    #
    # @example With audit logging
    #   RailsCron.configure do |config|
    #     config.lock_adapter = RailsCron::Lock::MySQLAdapter.new(log_dispatch: true)
    #   end
    class MySQLAdapter < Adapter
      # MySQL named locks have a maximum length of 64 characters
      MAX_LOCK_NAME_LENGTH = 64

      attr_reader :log_dispatch

      ##
      # Initialize a new MySQL adapter.
      #
      # @param log_dispatch [Boolean] whether to log dispatch attempts to CronDispatch model (default: false)
      def initialize(log_dispatch: false)
        super()
        @log_dispatch = log_dispatch
      end

      ##
      # Attempt to acquire a distributed lock using MySQL GET_LOCK.
      #
      # Uses MySQL's GET_LOCK(name, timeout) function with a timeout of 0 seconds
      # to perform non-blocking acquisition. If successful, records the dispatch
      # attempt if log_dispatch is enabled.
      #
      # **Note:** The +ttl+ parameter is ignored. MySQL named locks are connection-based
      # and do not have automatic expiration. The lock will be held until explicitly
      # released or the database connection is closed. See class documentation for
      # limitations.
      #
      # @param key [String] the lock key (format: "namespace:dispatch:cron_key:fire_time")
      # @param ttl [Integer] time-to-live in seconds (ignored; see class docs)
      # @return [Boolean] true if acquired, false if held by another process
      def acquire(key, _ttl)
        lock_name = truncate_lock_name(key)

        # GET_LOCK returns 1 on success, 0 on timeout, NULL on error
        sql = ActiveRecord::Base.sanitize_sql_array(['SELECT GET_LOCK(?, 0) as lock_result', lock_name])
        result_set = ActiveRecord::Base.connection.execute(sql)
        # Convert result to array and get first row, then first column value
        result_row = result_set.to_a.first
        result_value = result_row.is_a?(Hash) ? result_row['lock_result'] : result_row&.first
        acquired = cast_to_boolean(result_value)

        log_dispatch_attempt(key) if acquired && @log_dispatch

        acquired
      rescue StandardError => e
        raise LockAdapterError, "MySQL acquire failed for #{key}: #{e.message}"
      end

      ##
      # Release a distributed lock held by MySQL GET_LOCK.
      #
      # @param key [String] the lock key
      # @return [Boolean] true if released, false if not held
      def release(key)
        lock_name = truncate_lock_name(key)

        # RELEASE_LOCK returns 1 if held and released, 0 if not held, NULL on error
        sql = ActiveRecord::Base.sanitize_sql_array(['SELECT RELEASE_LOCK(?) as lock_result', lock_name])
        result_set = ActiveRecord::Base.connection.execute(sql)
        # Convert result to array and get first row, then first column value
        result_row = result_set.to_a.first
        result_value = result_row.is_a?(Hash) ? result_row['lock_result'] : result_row&.first
        cast_to_boolean(result_value)
      rescue StandardError => e
        raise LockAdapterError, "MySQL release failed for #{key}: #{e.message}"
      end

      private

      def cast_to_boolean(value)
        # MySQL GET_LOCK/RELEASE_LOCK returns 1 (success), 0 (failure), or NULL (error).
        # Cast integer/nil to boolean: 1 => true, 0 or nil => false.
        case value
        when 1
          true
        when 0, nil
          false
        when true, false
          value
        else
          !value.to_s.match?(/\A(0|f|false|)\z/i)
        end
      end

      def truncate_lock_name(key)
        # MySQL named lock names have a maximum length of 64 characters.
        # If the key exceeds this, truncate it and log a warning.
        if key.length > MAX_LOCK_NAME_LENGTH
          truncated_key = key[0...MAX_LOCK_NAME_LENGTH]
          Rails.logger.warn(
            "Lock key '#{key}' exceeds MySQL named lock limit of #{MAX_LOCK_NAME_LENGTH} characters. " \
            "Truncating to '#{truncated_key}'. This may cause lock collisions."
          )
          truncated_key
        else
          key
        end
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
