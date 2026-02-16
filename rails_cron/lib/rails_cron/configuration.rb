# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  ##
  # Configuration class for RailsCron
  # Holds all settings for the scheduler, tick intervals, locks, and more.
  #
  # @example Basic configuration
  #   RailsCron.configure do |config|
  #     config.tick_interval = 5
  #     config.lock_adapter = RailsCron::Lock::Redis.new(url: ENV["REDIS_URL"])
  #   end
  class Configuration
    # Default values for all configuration options
    DEFAULTS = {
      tick_interval: 5,
      window_lookback: 120,
      window_lookahead: 0,
      lease_ttl: 60,
      namespace: 'railscron',
      lock_adapter: nil,
      logger: nil,
      time_zone: nil
    }.freeze

    ##
    # Initialize a new Configuration instance with default values.
    #
    # @return [Configuration] a new instance with all defaults set
    def initialize
      @values = DEFAULTS.dup
    end

    ##
    # Retrieve or assign configuration values by method name.
    def method_missing(method_name, *args)
      handled, value = handle_known_key(method_name) do |key, setter|
        setter ? set_value(key, args.first) : @values[key]
      end

      return value if handled

      super
    end

    ##
    # Advertise supported configuration keys for respond_to?.
    def respond_to_missing?(method_name, include_private = false)
      handled, value = handle_known_key(method_name) { true }
      (handled && value) || super
    end

    ##
    # Validate configuration without raising.
    #
    # @return [Array<String>] validation error messages
    def validate
      validation_errors
    end

    ##
    # Validate the configuration settings.
    # Raises errors if required settings are invalid.
    #
    # @raise [ConfigurationError] if validation fails
    # @return [Configuration] self if validation passes
    def validate!
      errors = validation_errors
      raise ConfigurationError, errors.join('; ') if errors.any?

      self
    end

    ##
    # Get a hash representation of the current configuration.
    #
    # @return [Hash] configuration as a hash
    def to_h
      lock_adapter = @values[:lock_adapter]
      logger = @values[:logger]

      {
        tick_interval: @values[:tick_interval],
        window_lookback: @values[:window_lookback],
        window_lookahead: @values[:window_lookahead],
        lease_ttl: @values[:lease_ttl],
        namespace: @values[:namespace],
        lock_adapter: lock_adapter&.class&.name,
        logger: logger&.class&.name,
        time_zone: @values[:time_zone]
      }
    end

    private

    def validation_errors
      errors = []
      add_tick_interval_error(errors)
      add_window_lookback_error(errors)
      add_window_lookahead_error(errors)
      add_lease_ttl_error(errors)
      add_namespace_error(errors)
      errors
    end

    def add_tick_interval_error(errors)
      value = @values[:tick_interval]
      return unless value.to_i <= 0

      errors << "tick_interval must be greater than 0, got: #{value}"
    end

    def add_window_lookback_error(errors)
      value = @values[:window_lookback]
      return unless value.to_i.negative?

      errors << "window_lookback must be greater than or equal to 0, got: #{value}"
    end

    def add_window_lookahead_error(errors)
      value = @values[:window_lookahead]
      return unless value.to_i.negative?

      errors << "window_lookahead must be greater than or equal to 0, got: #{value}"
    end

    def add_lease_ttl_error(errors)
      value = @values[:lease_ttl]
      return unless value.to_i <= 0

      errors << "lease_ttl must be greater than 0, got: #{value}"
    end

    def add_namespace_error(errors)
      return unless @values[:namespace].to_s.strip.empty?

      errors << 'namespace cannot be empty'
    end

    def handle_known_key(method_name)
      name = method_name.to_s
      setter = name.end_with?('=')
      key = setter ? name.delete_suffix('=').to_sym : method_name.to_sym
      return [false, nil] unless @values.key?(key)

      [true, yield(key, setter)]
    end

    def set_value(key, value)
      @values[key] = normalize_value(key, value)
    end

    def normalize_value(key, value)
      return value unless @values.key?(key)

      case key
      when :tick_interval, :window_lookback, :window_lookahead, :lease_ttl
        value.to_i
      when :namespace
        value.to_s
      when :time_zone
        value&.to_s
      else
        value
      end
    end
  end

  ##
  # Error raised when configuration is invalid.
  class ConfigurationError < StandardError; end
end
