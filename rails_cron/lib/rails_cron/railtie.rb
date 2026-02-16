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
    # Captures and chains any previously registered handlers to cooperate with other components.
    def self.register_signal_handlers
      logger = RailsCron.logger

      %w[TERM INT].each do |signal|
        # Capture the previous handler by temporarily setting to IGNORE and restoring
        old_handler = Signal.trap(signal, 'IGNORE')
        Signal.trap(signal, old_handler) if old_handler && old_handler != 'IGNORE'

        # Now install our handler that chains to the previous one
        Signal.trap(signal) do
          handle_shutdown_signal(signal, old_handler, logger)
        end
      end
    rescue StandardError => e
      logger&.warn("Failed to register signal handlers: #{e.full_message}")
    end

    ##
    # Handle a shutdown signal and chain to previous handler.
    def self.handle_shutdown_signal(signal, old_handler, logger)
      logger&.info("Received #{signal} signal, stopping scheduler...")
      begin
        stopped = RailsCron.stop!(timeout: 30)
        logger&.warn('Scheduler did not stop within timeout, thread may still be running') unless stopped
      rescue StandardError => e
        logger&.error("Error stopping scheduler on #{signal} signal: #{e.full_message}")
      end

      chain_previous_handler(signal, old_handler, logger)
    end

    ##
    # Chain to a previous signal handler if it exists.
    def self.chain_previous_handler(signal, old_handler, logger)
      if old_handler.respond_to?(:call)
        old_handler.call
      elsif old_handler.is_a?(String) && old_handler != 'DEFAULT' && old_handler != 'IGNORE'
        # If previous handler was a command string, we can't easily re-invoke it
        logger&.debug("Previous #{signal} handler was a command: #{old_handler}")
      end
    end

    ##
    # Autoload paths for RailsCron models and other components
    initializer 'rails_cron.autoload' do |_app|
      models_path = File.expand_path('../../app/models', __dir__)
      Rails.autoloaders.main.push_dir(models_path)
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

      logger = RailsCron.logger

      logger&.info('Rails is shutting down, stopping RailsCron scheduler...')
      begin
        stopped = RailsCron.stop!(timeout: 10)
        return if stopped

        pid = Process.pid
        message_array = [
          'RailsCron scheduler did not stop within timeout.',
          "Process #{pid} may still be running. You may need to kill it manually with `kill -9 #{pid}`."
        ]
        logger&.warn(message_array.join(' '))
      rescue StandardError => e
        logger&.error("Error stopping scheduler during shutdown: #{e.message}")
      end
    end

    ##
    # Ensure graceful shutdown on Rails shutdown.
    at_exit do
      RailsCron::Railtie.handle_shutdown
    end
  end
end
