# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'

module IntegrationLockHelper
  def configure_lock_adapter(adapter_instance, adapter_label)
    @previous_lock_adapter = RailsCron.lock_adapter
    @previous_db_config = ActiveRecord::Base.connection_db_config

    configure_database(adapter_label)
    RailsCron.configure do |config|
      config.lock_adapter = adapter_instance
    end
  end

  def restore_lock_adapter
    RailsCron.configure do |config|
      config.lock_adapter = @previous_lock_adapter
    end

    ActiveRecord::Base.establish_connection(@previous_db_config) if @previous_db_config
  end

  def lock_adapter
    RailsCron.lock_adapter
  end

  def integration_key_prefix(label)
    @integration_key_prefix ||= {}
    @integration_key_prefix[label] ||= "rails-cron:int:#{label}:#{SecureRandom.hex(4)}"
  end

  def integration_lock_key(label, suffix)
    @integration_used_keys ||= Hash.new { |hash, key| hash[key] = [] }
    key = "#{integration_key_prefix(label)}:#{suffix}"
    @integration_used_keys[label] << key
    key
  end

  def integration_used_keys(label)
    @integration_used_keys ||= Hash.new { |hash, key| hash[key] = [] }
    @integration_used_keys[label]
  end

  def lock_key(suffix)
    integration_lock_key(adapter_label, suffix)
  end

  def cleanup_lock_keys(label)
    # PostgreSQL and MySQL have connection-based locks that auto-release when the
    # connection closes. Attempting to release from a different connection causes
    # warnings (e.g., PostgreSQL: "you don't own a lock of type ExclusiveLock").
    # Only cleanup adapters that need explicit release.
    return if %w[pg mysql].include?(label)

    integration_used_keys(label).each do |key|
      lock_adapter.release(key)
    rescue StandardError
      # Ignore cleanup failures for expired or foreign locks.
    end
    integration_used_keys(label).clear
  end

  def with_held_lock(key, ttl: 30, hold_for: 0.1)
    # PostgreSQL and MySQL adapters require connection pool handling for separate connections
    thread = if [RailsCron::Lock::PostgresAdapter, RailsCron::Lock::MySQLAdapter].any? { |klass| lock_adapter.is_a?(klass) }
               Thread.new do
                 ActiveRecord::Base.connection_pool.with_connection do
                   adapter_class = lock_adapter.class
                   adapter_kwargs = lock_adapter.log_dispatch ? { log_dispatch: lock_adapter.log_dispatch } : {}
                   adapter_class.new(**adapter_kwargs).with_lock(key, ttl: ttl) { sleep hold_for }
                 end
               end
             else
               Thread.new do
                 lock_adapter.with_lock(key, ttl: ttl) { sleep hold_for }
               end
             end

    sleep 0.02
    yield
  ensure
    thread&.join
  end

  def configure_database(adapter_label)
    case adapter_label
    when 'pg'
      database_url = ENV.fetch('DATABASE_URL', nil)
      raise 'DATABASE_URL must be set for pg integration tests' if database_url.to_s.strip.empty?

      ActiveRecord::Base.establish_connection(database_url)
      ActiveRecord::Migration.maintain_test_schema!
    when 'mysql'
      database_url = ENV.fetch('DATABASE_URL', nil)
      raise 'DATABASE_URL must be set for mysql integration tests' if database_url.to_s.strip.empty?

      ActiveRecord::Base.establish_connection(database_url)
      ActiveRecord::Migration.maintain_test_schema!
    when 'sqlite'
      ActiveRecord::Base.establish_connection(:test)
      ActiveRecord::Migration.maintain_test_schema!
    else
      ActiveRecord::Base.establish_connection(:test)
    end
  end
end
