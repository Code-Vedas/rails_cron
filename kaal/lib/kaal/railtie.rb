# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'pathname'

module Kaal
  ##
  # Railtie class to integrate Kaal with Rails applications.
  # Initializes configuration, sets up the default logger, and handles signal management.
  class Railtie < ::Rails::Railtie
    ##
    # Ensure configuration logger uses Rails.logger when available.
    def self.ensure_logger!
      logger = Rails.logger
      return unless logger

      Kaal.configure do |config|
        config.logger ||= logger
      end
    rescue NoMethodError
      nil
    end

    ##
    # Register signal handlers for graceful shutdown.
    # Captures and chains any previously registered handlers to cooperate with other components.
    def self.register_signal_handlers
      logger = Kaal.logger

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
        stopped = Kaal.stop!(timeout: 30)
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
    # Load scheduler file at boot while respecting missing-file policy.
    def self.load_scheduler_file_on_boot!
      configuration = fetch_configuration_for_boot
      return unless configuration

      if configuration.scheduler_missing_file_policy == :error
        load_scheduler_file_now!
        return
      end

      scheduler_path = configuration.scheduler_config_path.to_s.strip
      return if scheduler_path.empty?

      absolute_path = resolve_scheduler_path(scheduler_path)
      unless File.exist?(absolute_path)
        Kaal.logger&.warn("Scheduler file not found at #{absolute_path}")
        return
      end

      load_scheduler_file_now!
    end

    def self.resolve_scheduler_path(path)
      candidate = Pathname.new(path)
      candidate.absolute? ? candidate.to_s : Rails.root.join(candidate).to_s
    end

    def self.load_scheduler_file_now!
      Kaal.load_scheduler_file!
    end

    def self.fetch_configuration_for_boot
      Kaal.configuration
    rescue NameError => e
      Kaal.logger&.debug("Skipping scheduler file boot load due to configuration error: #{e.message}")
      nil
    end

    ##
    # Autoload paths for Kaal models and other components
    initializer 'kaal.autoload' do |_app|
      models_path = File.expand_path('../../app/models', __dir__)
      Rails.autoloaders.main.push_dir(models_path)
    end

    ##
    # Initialize Kaal when Rails boots.
    # Sets the default logger to Rails.logger if available.
    initializer 'kaal.configuration' do |_app|
      # Set default logger to Rails.logger if not already configured
      Kaal::Railtie.ensure_logger!
    end

    ##
    # Load gem i18n files into Rails I18n load path for host applications.
    initializer 'kaal.i18n', before: 'i18n.load_path' do |app|
      locales = Dir[File.expand_path('../../config/locales/*.yml', __dir__)]
      app.config.i18n.load_path |= locales
    end

    ##
    # Load rake tasks into host Rails applications.
    rake_tasks do
      load File.expand_path('../tasks/kaal_tasks.rake', __dir__)
    end

    ##
    # Load the default initializer after Rails has finished initialization.
    # This ensures Rails.logger is fully available and sets up signal handlers.
    config.after_initialize do
      # Re-ensure logger is set in case it wasn't available during first initializer
      Kaal::Railtie.ensure_logger!

      # Load scheduler definitions from file when available (or required by policy)
      Kaal::Railtie.load_scheduler_file_on_boot!

      # Register signal handlers for graceful shutdown
      Kaal::Railtie.register_signal_handlers
    end

    ##
    # Handle graceful shutdown when Rails exits.
    def self.handle_shutdown
      return unless Kaal.running?

      logger = Kaal.logger

      logger&.info('Rails is shutting down, stopping Kaal scheduler...')
      begin
        stopped = Kaal.stop!(timeout: 10)
        return if stopped

        pid = Process.pid
        message_array = [
          'Kaal scheduler did not stop within timeout.',
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
      Kaal::Railtie.handle_shutdown
    end
  end
end
