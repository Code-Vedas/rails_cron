# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'securerandom'
require 'timeout'

module IntegrationLockHelper
  def configure_backend(adapter_instance, adapter_label)
    @previous_backend = Kaal.backend
    @previous_db_config = ActiveRecord::Base.connection_db_config

    configure_database(adapter_label)
    Kaal.configure do |config|
      config.backend = adapter_instance
    end
  end

  def restore_backend
    Kaal.configure do |config|
      config.backend = @previous_backend
    end

    ActiveRecord::Base.establish_connection(@previous_db_config) if @previous_db_config
  end

  def backend
    Kaal.backend
  end

  def integration_key_prefix(label)
    @integration_key_prefix ||= {}
    @integration_key_prefix[label] ||= "kaal:int:#{label}:#{SecureRandom.hex(4)}"
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
      backend.release(key)
    rescue StandardError
      # Ignore cleanup failures for expired or foreign locks.
    end
    integration_used_keys(label).clear
  end

  def with_held_lock(key, ttl: 30, hold_for: 0.1)
    acquired_signal = Queue.new
    thread = Thread.new { hold_lock_in_thread(key:, ttl:, hold_for:, acquired_signal:) }

    signal = Timeout.timeout(1) { acquired_signal.pop }
    raise signal if signal.is_a?(StandardError)
    raise "Failed to acquire held lock for #{key}" unless signal == :acquired

    yield
  rescue Timeout::Error
    raise "Timed out waiting for held lock #{key} to be acquired"
  ensure
    thread&.join
  end

  private

  def hold_lock_in_thread(key:, ttl:, hold_for:, acquired_signal:)
    hold_lock = lambda do |lock_adapter|
      signaled = false

      lock_adapter.with_lock(key, ttl: ttl) do
        signaled = true
        acquired_signal << :acquired
        sleep hold_for
      end

      acquired_signal << :not_acquired unless signaled
    end

    if advisory_lock_adapter?
      ActiveRecord::Base.connection_pool.with_connection do
        hold_lock.call(backend.class.new)
      end
    else
      hold_lock.call(backend)
    end
  rescue StandardError => e
    acquired_signal << e
  end

  def advisory_lock_adapter?
    [Kaal::Backend::PostgresAdapter, Kaal::Backend::MySQLAdapter].any? { |klass| backend.is_a?(klass) }
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
    when 'redis'
      redis_url = ENV.fetch('REDIS_URL', nil)
      raise 'REDIS_URL must be set for redis integration tests' if redis_url.to_s.strip.empty?
    else
      ActiveRecord::Base.establish_connection(:test)
    end
  end
end
