# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fugit'

module RailsCron
  ##
  # Coordinator manages the main scheduler loop that calculates due fire times
  # and dispatches cron work safely across multiple nodes using distributed locks.
  #
  # The coordinator:
  # 1. Runs a background thread on tick_interval
  # 2. For each registered cron, calculates due fire times within the window
  # 3. Attempts to acquire a distributed lease for each due time
  # 4. Calls the enqueue callback if the lease is acquired
  # 5. Supports graceful shutdown and re-entrancy for testing
  #
  # @example Start the coordinator
  #   coordinator = RailsCron::Coordinator.new
  #   coordinator.start!
  #
  # @example Manual tick execution (for testing)
  #   coordinator.tick!
  #
  # @example Stop the coordinator
  #   coordinator.stop!
  class Coordinator
    ##
    # Initialize a new Coordinator instance.
    #
    # @param configuration [Configuration] the scheduler configuration
    # @param registry [Registry] the registered crons registry
    def initialize(configuration:, registry:)
      @configuration = configuration
      @registry = registry
      @thread = nil
      @running = false
      @stop_requested = false
      @mutex = Mutex.new
      @tick_cv = ConditionVariable.new
    end

    ##
    # Start the coordinator background thread.
    #
    # @return [Thread] the started thread, or nil if already running
    # @safe
    def start!
      @mutex.synchronize do
        return nil if @running

        @running = true
        @stop_requested = false
        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = true
        return @thread
      end
    end

    ##
    # Stop the coordinator gracefully.
    #
    # Signals the coordinator to stop after the current tick completes,
    # then waits for the thread to finish.
    #
    # @param timeout [Integer] seconds to wait for graceful shutdown (default: 30)
    # @return [Boolean] true if stopped, false if timeout
    # @safe
    def stop!(timeout: 30) # rubocop:disable Naming/PredicateMethod
      request_stop

      # Wait for thread to finish outside the lock
      result = @thread&.join(timeout)

      # If we had a thread and join timed out, thread is still alive
      return false if @thread && result.nil?

      @thread = nil
      @mutex.synchronize { @running = false }

      true
    end

    ##
    # Check if the coordinator is currently running.
    #
    # @return [Boolean] true if running, false otherwise
    def running?
      @mutex.synchronize { @running }
    end

    ##
    # Restart the coordinator (stop then start).
    #
    # @return [Thread] the started thread
    # @safe
    def restart!
      stop!
      start!
    end

    ##
    # Execute a single tick manually.
    #
    # This is useful for testing and Rake tasks that want to trigger
    # the scheduler without running the background loop.
    #
    # @return [void]
    # @safe
    def tick!
      execute_tick
    end

    ##
    # Reset coordinator state for re-entrancy in tests.
    #
    # Stops any running thread before clearing state to avoid orphaning it.
    # Raises an error if the thread cannot be stopped within the timeout.
    #
    # @return [void]
    # @raise [RuntimeError] if stop! times out
    # @safe
    def reset!
      # Stop any running thread first to prevent orphaned threads
      if running?
        stopped = stop!
        raise 'Failed to stop coordinator thread within timeout' unless stopped
      end

      # Now safe to reset all state
      @mutex.synchronize do
        @running = false
        @stop_requested = false
        @thread = nil
      end
    end

    private

    def request_stop
      @mutex.synchronize do
        return unless @running

        @stop_requested = true
        @tick_cv.signal
      end
    end

    def run_loop
      loop do
        break if stop_requested?

        execute_tick
        sleep_until_next_tick
      end
    ensure
      @mutex.synchronize { @running = false }
    end

    def stop_requested?
      @mutex.synchronize { @stop_requested }
    end

    def execute_tick
      @registry.each do |entry|
        calculate_and_dispatch_due_times(entry)
      end
    rescue StandardError => e
      # Log error but continue the loop
      @configuration.logger&.error("RailsCron coordinator tick failed: #{e.message}")
    end

    def calculate_and_dispatch_due_times(entry)
      now = Time.current
      window_start = now - @configuration.window_lookback
      window_end = now + @configuration.window_lookahead

      # Parse cron expression using fugit
      cron = parse_cron(entry.cron)
      return unless cron

      # Find all occurrences within the window
      occurrences = find_occurrences(cron, window_start, window_end)
      @configuration.logger&.debug("Coordinator: Found #{occurrences.length} occurrences for #{entry.key} in window [#{window_start}, #{window_end}]")

      # For each occurrence that's due (in the past or now), try to dispatch
      occurrences.each do |fire_time|
        dispatch_if_due(entry, fire_time, now)
      end
    end

    def parse_cron(cron_expression)
      result = Fugit.parse_cron(cron_expression)
      raise ArgumentError, "Invalid cron expression: #{cron_expression}" unless result

      result
    rescue ArgumentError => e
      @configuration.logger&.warn("Failed to parse cron expression '#{cron_expression}': #{e.message}")
      nil
    end

    def find_occurrences(cron, start_time, end_time)
      # Use fugit to find all occurrences between start and end times
      occurrences = []
      current_time = start_time

      while current_time <= end_time
        next_occurrence = cron.next_time(current_time)
        break unless next_occurrence

        break if next_occurrence > end_time

        occurrences << next_occurrence
        current_time = next_occurrence + 1.second # Move past this occurrence to find the next
      end

      occurrences
    rescue StandardError => e
      @configuration.logger&.error("Failed to calculate occurrences: #{e.message}")
      []
    end

    def dispatch_if_due(entry, fire_time, now)
      # Only dispatch if fire_time is in the past or now
      return if fire_time > now

      logger = @configuration.logger
      cron_key = entry.key

      # Generate a unique lock key for this fire time
      lock_key = generate_lock_key(cron_key, fire_time)

      # Try to acquire the lock
      if acquire_lock(lock_key)
        dispatch_work(entry, fire_time)
      else
        logger&.debug("Failed to acquire lock for #{lock_key}")
      end
    rescue StandardError => e
      cron_key ||= 'unknown'
      logger&.error("Error dispatching work for #{cron_key}: #{e.message}")
    end

    def acquire_lock(lock_key)
      lock_adapter = @configuration.lock_adapter
      logger = @configuration.logger

      # No adapter = no locking (dev/test)
      return true unless lock_adapter

      lock_adapter.acquire(lock_key, @configuration.lease_ttl)
    rescue StandardError => e
      logger&.error("Lock acquisition failed for #{lock_key}: #{e.message}")
      false
    end

    def dispatch_work(entry, fire_time)
      # Call the enqueue callback with fire_time and idempotency_key
      cron_key = entry.key
      logger = @configuration.logger

      idempotency_key = generate_idempotency_key(cron_key, fire_time)
      entry.enqueue.call(fire_time:, idempotency_key:)
      logger&.debug("Dispatched work for #{cron_key} at #{fire_time}")
    rescue StandardError => e
      logger&.error("Work dispatch failed for #{cron_key}: #{e.message}")
    end

    def generate_idempotency_key(cron_key, fire_time)
      namespace = @configuration.namespace || 'railscron'
      "#{namespace}-#{cron_key}-#{fire_time.to_i}"
    end

    def generate_lock_key(cron_key, fire_time)
      namespace = @configuration.namespace || 'railscron'
      "#{namespace}-dispatch-lock-#{cron_key}-#{fire_time.to_i}"
    end

    def sleep_until_next_tick
      @mutex.synchronize do
        @tick_cv.wait(@mutex, @configuration.tick_interval)
      end
    rescue StandardError => e
      @configuration.logger&.error("Sleep interrupted: #{e.message}")
    end
  end
end
