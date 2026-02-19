# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails_cron/version'
require 'rails_cron/configuration'
require 'rails_cron/registry'
require 'rails_cron/dispatch/registry'
require 'rails_cron/dispatch/memory_engine'
require 'rails_cron/dispatch/redis_engine'
require 'rails_cron/dispatch/database_engine'
require 'rails_cron/lock/adapter'
require 'rails_cron/lock/memory_adapter'
require 'rails_cron/lock/redis_adapter'
require 'rails_cron/lock/postgres_adapter'
require 'rails_cron/lock/mysql_adapter'
require 'rails_cron/lock/sqlite_adapter'
require 'rails_cron/idempotency_key_generator'
require 'rails_cron/coordinator'
require 'rails_cron/railtie'

##
# RailsCron module is the main namespace for the gem.
# Provides configuration, job registration, and registry access.
#
# @example Configure RailsCron
#   RailsCron.configure do |config|
#     config.tick_interval = 5
#     config.lock_adapter = RailsCron::Lock::RedisAdapter.new(Redis.new(url: ENV["REDIS_URL"]))
#   end
#
# @example Register a cron job
#   RailsCron.register(
#     key: "reports:daily",
#     cron: "0 9 * * *",
#     enqueue: ->(fire_time:, idempotency_key:) { MyJob.perform_later }
#   )
module RailsCron
  class << self
    ##
    # Get the current configuration instance.
    #
    # @return [Configuration] the global configuration object
    def configuration
      @configuration ||= Configuration.new
    end

    ##
    # Get the current registry instance.
    #
    # @return [Registry] the global registry object
    def registry
      @registry ||= Registry.new
    end

    ##
    # Get the coordinator instance.
    #
    # @return [Coordinator] the global coordinator object
    def coordinator
      @coordinator ||= Coordinator.new(configuration: configuration, registry: registry)
    end

    ##
    # Reset configuration to defaults. Primarily used in tests.
    #
    # @return [Configuration] a fresh configuration object
    def reset_configuration!
      @configuration = Configuration.new
      @coordinator = nil # Invalidate coordinator so it rebuilds with new config
    end

    ##
    # Reset registry to empty state. Primarily used in tests.
    #
    # @return [Registry] a fresh registry object
    def reset_registry!
      @registry = Registry.new
      @coordinator = nil # Invalidate coordinator so it rebuilds with new registry
    end

    ##
    # Reset coordinator to initial state. Primarily used in tests.
    #
    # Stops any running coordinator and creates a fresh instance.
    #
    # @return [Coordinator] a fresh coordinator object
    # @raise [RuntimeError] if the running coordinator cannot be stopped within timeout
    def reset_coordinator!
      # Stop the existing coordinator if it's running
      if @coordinator&.running?
        stopped = @coordinator.stop!
        raise 'Failed to stop coordinator thread within timeout' unless stopped
      end

      # Create and return a fresh coordinator
      @coordinator = nil
      coordinator
    end

    ##
    # Configure RailsCron via a block.
    #
    # @yield [config] yields the configuration object
    # @yieldparam config [Configuration] the configuration instance to customize
    # @return [void]
    #
    # @example
    #   RailsCron.configure do |config|
    #     config.tick_interval = 10
    #     config.lease_ttl = 120
    #   end
    def configure
      yield(configuration) if block_given?
    end

    ##
    # Register a new cron job.
    #
    # @param key [String] unique identifier for the cron task
    # @param cron [String] cron expression (e.g., "0 9 * * *", "@daily")
    # @param enqueue [Proc, Lambda] callable executed when cron fires
    # @return [Registry::Entry] the registered entry
    #
    # @raise [ArgumentError] if parameters are invalid
    # @raise [RegistryError] if key is already registered
    #
    # @example
    #   RailsCron.register(
    #     key: "reports:weekly_summary",
    #     cron: "0 9 * * 1",
    #     enqueue: ->(fire_time:, idempotency_key:) { WeeklySummaryJob.perform_later }
    #   )
    def register(key:, cron:, enqueue:)
      registry.add(key: key, cron: cron, enqueue: enqueue)
    end

    ##
    # Unregister (remove) a cron job by key.
    #
    # @param key [String] the unique identifier of the job to remove
    # @return [Registry::Entry, nil] the removed entry, or nil if not found
    #
    # @example
    #   RailsCron.unregister(key: "reports:daily")
    def unregister(key:)
      registry.remove(key)
    end

    ##
    # Get all registered cron jobs.
    #
    # @return [Array<Registry::Entry>] array of all registered entries
    #
    # @example
    #   RailsCron.registered.each { |entry| puts entry.key }
    def registered
      registry.all
    end

    ##
    # Check if a cron job is registered by key.
    #
    # @param key [String] the unique identifier to check
    # @return [Boolean] true if the key is registered, false otherwise
    #
    # @example
    #   RailsCron.registered?(key: "reports:daily") # => true
    def registered?(key:)
      registry.registered?(key)
    end

    ##
    # Start the scheduler background thread.
    #
    # The coordinator will calculate due fire times for each registered cron
    # on each tick and attempt to dispatch work.
    #
    # @return [Thread] the started thread, or nil if already running
    #
    # @example
    #   RailsCron.start!
    def start!
      coordinator.start!
    end

    ##
    # Stop the scheduler gracefully.
    #
    # Signals the coordinator to stop after the current tick completes,
    # then waits for the thread to finish.
    #
    # @param timeout [Integer] seconds to wait for graceful shutdown (default: 30)
    # @return [Boolean] true if stopped successfully
    #
    # @example
    #   RailsCron.stop!
    # @example
    #   RailsCron.stop!(timeout: 60)
    def stop!(timeout: 30)
      coordinator.stop!(timeout: timeout)
    end

    ##
    # Check if the scheduler is currently running.
    #
    # @return [Boolean] true if running, false otherwise
    #
    # @example
    #   if RailsCron.running?
    #     puts "Scheduler is active"
    #   end
    def running?
      coordinator.running?
    end

    ##
    # Restart the scheduler (stop then start).
    #
    # @return [Thread] the started thread
    #
    # @example
    #   RailsCron.restart!
    def restart!
      coordinator.restart!
    end

    ##
    # Execute a single scheduler tick manually.
    #
    # This is useful for testing and Rake tasks that want to trigger
    # the scheduler without running the background loop.
    #
    # @return [void]
    #
    # @example
    #   RailsCron.tick!
    def tick!
      coordinator.tick!
    end

    ##
    # Generate an idempotency key for a cron job and yield to a block.
    #
    # Useful for advanced use cases where you need to generate an idempotency key
    # outside of the normal enqueue flow, or for internal utilities.
    #
    # @param key [String] the cron job key
    # @param fire_time [Time] the fire time
    # @yield [String] yields the generated idempotency key
    # @return [Object] the result of the block
    #
    # @example
    #   RailsCron.with_idempotency('reports:daily', Time.current) do |idempotency_key|
    #     MyJob.perform_later(key: idempotency_key)
    #   end
    def with_idempotency(key, fire_time)
      generator = IdempotencyKeyGenerator.new(configuration: configuration)
      idempotency_key = generator.call(key, fire_time)
      yield(idempotency_key)
    end

    ##
    # Check if a cron job has already been dispatched for a given fire time.
    #
    # Useful for implementing deduplication logic to prevent duplicate job enqueues.
    # Returns true if dispatch logging is enabled and the job was previously dispatched,
    # returns false if not found or dispatch logging is disabled.
    #
    # Safe to call from enqueue callbacks - will return false on any error (e.g., backend
    # misconfiguration or temporary failure), log via configuration.logger, and never raise.
    #
    # @param key [String] the cron job key
    # @param fire_time [Time] the fire time to check
    # @return [Boolean] true if dispatch exists, false otherwise (never raises)
    #
    # @example
    #   RailsCron.dispatched?('reports:daily', Time.current)
    #   # => true if already dispatched, false otherwise
    def dispatched?(key, fire_time)
      adapter = configuration.lock_adapter
      return false if adapter.nil? || !adapter.respond_to?(:dispatch_registry)

      adapter.dispatch_registry.dispatched?(key, fire_time)
    rescue StandardError => e
      configuration.logger&.warn("Error checking dispatch status for #{key}: #{e.message}")
      false
    end

    ##
    # Get the dispatch log registry for querying dispatch history.
    #
    # Returns the underlying dispatch registry engine which allows querying
    # dispatch records. The specific methods available depend on the adapter type:
    #
    # **Common methods (all adapters):**
    # - `find_dispatch(key, fire_time)` - Find a specific dispatch record
    # - `dispatched?(key, fire_time)` - Check if a dispatch exists
    #
    # **Database adapter specific methods:**
    # - `find_by_key(key)` - Find all dispatches for a job key
    # - `find_by_node(node_id)` - Find all dispatches from a node, ordered by fire_time
    # - `find_by_status(status)` - Find dispatches by status ('dispatched', 'failed', etc.)
    # - `cleanup(recovery_window: 86400)` - Delete dispatch records older than window
    #
    # **Redis adapter:**
    # - Uses automatic TTL expiration (no cleanup needed)
    #
    # **Memory adapter (development/testing):**
    # - `clear()` - Clear all stored records
    # - `size()` - Get count of stored records
    #
    # Safe for production diagnostics - will return nil on any error (e.g., backend
    # misconfiguration or temporary failure), log via configuration.logger, and never raise.
    #
    # @return [Dispatch::Registry, nil] the dispatch registry instance, or nil if adapter doesn't support it or on error
    #
    # @example Query dispatches with database adapter
    #   registry = RailsCron.dispatch_log_registry
    #   # Find all dispatches for a job
    #   registry.find_by_key('reports:daily')
    #   # Find failed attempts
    #   registry.find_by_status('failed')
    #   # Clean up old records (over 30 days old)
    #   registry.cleanup(recovery_window: 30 * 24 * 60 * 60)
    #
    # @example Query dispatches with memory adapter
    #   registry = RailsCron.dispatch_log_registry
    #   record = registry.find_dispatch('reports:daily', Time.current)
    #   total = registry.size
    #   registry.clear
    def dispatch_log_registry
      adapter = configuration.lock_adapter
      return nil if adapter.nil? || !adapter.respond_to?(:dispatch_registry)

      adapter.dispatch_registry
    rescue StandardError => e
      configuration.logger&.warn("Error accessing dispatch registry: #{e.message}")
      nil
    end

    ##
    # Configuration accessors for convenience.
    def tick_interval
      configuration.tick_interval
    end

    def tick_interval=(value)
      configuration.tick_interval = value
    end

    def window_lookback
      configuration.window_lookback
    end

    def window_lookback=(value)
      configuration.window_lookback = value
    end

    def window_lookahead
      configuration.window_lookahead
    end

    def window_lookahead=(value)
      configuration.window_lookahead = value
    end

    def lease_ttl
      configuration.lease_ttl
    end

    def lease_ttl=(value)
      configuration.lease_ttl = value
    end

    def namespace
      configuration.namespace
    end

    def namespace=(value)
      configuration.namespace = value
    end

    def lock_adapter
      configuration.lock_adapter
    end

    def lock_adapter=(value)
      configuration.lock_adapter = value
    end

    def logger
      configuration.logger
    end

    def logger=(value)
      configuration.logger = value
    end

    def time_zone
      configuration.time_zone
    end

    def time_zone=(value)
      configuration.time_zone = value
    end

    def validate
      configuration.validate
    end

    def validate!
      configuration.validate!
    end
  end
end
