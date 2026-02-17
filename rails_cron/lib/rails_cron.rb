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
require 'rails_cron/coordinator'
require 'rails_cron/railtie'

##
# RailsCron module is the main namespace for the gem.
# Provides configuration, job registration, and registry access.
#
# @example Configure RailsCron
#   RailsCron.configure do |config|
#     config.tick_interval = 5
#     config.lock_adapter = RailsCron::Lock::Redis.new(url: ENV["REDIS_URL"])
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
