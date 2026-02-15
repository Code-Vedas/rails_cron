# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  ##
  # Railtie class to integrate RailsCron with Rails applications.
  # Initializes configuration and sets up the default logger on Rails boot.
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
    # Initialize RailsCron when Rails boots.
    # Sets the default logger to Rails.logger if available.
    initializer 'rails_cron.configuration' do |_app|
      # Set default logger to Rails.logger if not already configured
      RailsCron::Railtie.ensure_logger!
    end

    ##
    # Load the default initializer after Rails has finished initialization.
    # This ensures Rails.logger is fully available.
    config.after_initialize do
      # Re-ensure logger is set in case it wasn't available during first initializer
      RailsCron::Railtie.ensure_logger!
    end
  end
end
