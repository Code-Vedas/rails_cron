# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  ##
  # Railtie class to integrate RailsCron with Rails applications.
  # Initializes configuration, sets up the default logger, and handles signal management.
  class Railtie < ::Rails::Railtie
    ##
    # Ensure configuration logger uses Rails.logger when available.
    def self.ensure_logger!
      logger = Rails.logger
      return unless logger

      RailsCron.configure do |config|
        config.logger ||= logger
      end
    rescue NoMethodError
      nil
    end

    ##
    # Register signal handlers for graceful shutdown.
    def self.register_signal_handlers
      logger = RailsCron.logger

      %w[TERM INT].each do |signal|
        Signal.trap(signal) do
          logger&.info("Received #{signal} signal, stopping scheduler...")
          RailsCron.stop!(timeout: 30)
        end
      end
    rescue StandardError => e
      logger&.warn("Failed to register signal handlers: #{e.message}")
    end

    ##
    # Initialize RailsCron when Rails boots.
    # Sets the default logger to Rails.logger if available.
    initializer 'rails_cron.configuration' do |_app|
      # Set default logger to Rails.logger if not already configured
      RailsCron::Railtie.ensure_logger!
    end

    ##
    # Load the default initializer after Rails has finished initialization.
    # This ensures Rails.logger is fully available and sets up signal handlers.
    config.after_initialize do
      # Re-ensure logger is set in case it wasn't available during first initializer
      RailsCron::Railtie.ensure_logger!

      # Register signal handlers for graceful shutdown
      RailsCron::Railtie.register_signal_handlers
    end

    ##
    # Handle graceful shutdown when Rails exits.
    def self.handle_shutdown
      return unless RailsCron.running?

      RailsCron.logger&.info('Rails is shutting down, stopping RailsCron scheduler...')
      RailsCron.stop!(timeout: 10)
    end

    ##
    # Ensure graceful shutdown on Rails shutdown.
    at_exit do
      RailsCron::Railtie.handle_shutdown
    end
  end
end
