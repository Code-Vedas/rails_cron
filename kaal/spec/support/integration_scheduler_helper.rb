# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'yaml'

module IntegrationSchedulerHelper
  include IntegrationLockHelper

  class EventRecorder
    def initialize
      @events = []
      @mutex = Mutex.new
      @condition_variable = ConditionVariable.new
    end

    def record(event)
      @mutex.synchronize do
        @events << event
        @condition_variable.broadcast
      end
    end

    def snapshot
      @mutex.synchronize { @events.map(&:dup) }
    end

    def wait_for_count(count, timeout: 2)
      wait_until(timeout: timeout, description: "at least #{count} events") { @events.length >= count }
      snapshot
    end

    private

    def wait_until(timeout:, description:)
      deadline = monotonic_time + timeout

      @mutex.synchronize do
        until yield
          remaining = deadline - monotonic_time
          raise "Timed out waiting for #{description} within #{timeout} seconds" if remaining <= 0

          @condition_variable.wait(@mutex, remaining)
        end
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  def configure_scheduler_backend(adapter_instance, adapter_label)
    configure_backend(adapter_instance, adapter_label)

    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline

    Kaal.configure do |config|
      config.backend = adapter_instance
      config.tick_interval = 1
      config.window_lookback = 30
      config.window_lookahead = 0
      config.lease_ttl = 31
      config.namespace = integration_key_prefix(adapter_label)
      config.enable_dispatch_recovery = false
      config.scheduler_missing_file_policy = :error
      config.logger = Logger.new(StringIO.new)
    end
  end

  def cleanup_scheduler_state(adapter_label)
    ActiveJob::Base.queue_adapter = @previous_queue_adapter if defined?(@previous_queue_adapter) && @previous_queue_adapter

    scheduler_definition_keys(adapter_label).each do |key|
      Kaal.definition_registry.remove_definition(key)
    rescue StandardError => e
      warn "[IntegrationSchedulerHelper] Failed to remove scheduler definition #{key.inspect}: #{e.class}: #{e.message}"
    end
    scheduler_definition_keys(adapter_label).clear

    FileUtils.rm_rf(@scheduler_tmpdir) if defined?(@scheduler_tmpdir) && @scheduler_tmpdir
    @scheduler_tmpdir = nil
  end

  def build_event_recorder
    EventRecorder.new
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    until yield
      raise "Timed out after #{timeout} seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  def register_code_job(key:, recorder:, source: 'code', cron: '* * * * *')
    remember_scheduler_definition_key(key)
    Kaal.register(
      key: key,
      cron: cron,
      enqueue: lambda do |fire_time:, idempotency_key:|
        recorder.record(
          key: key,
          source: source,
          fire_time: fire_time.utc,
          idempotency_key:
        )
      end
    )
  end

  def scheduler_key(suffix)
    key = "#{integration_key_prefix(adapter_label)}:scheduler:#{suffix}"
    remember_scheduler_definition_key(key)
    key
  end

  def integration_tick_time(offset_minutes = 0)
    Time.utc(2026, 1, 1, 12, offset_minutes, 5)
  end

  def expected_fire_time(time)
    Time.utc(time.year, time.month, time.day, time.hour, time.min, 0)
  end

  def tick_scheduler(at:, coordinator: Kaal.coordinator)
    travel_to(at) do
      coordinator.tick!
    end
  end

  def build_inline_job_class(recorder)
    klass = Class.new(ActiveJob::Base) do
      class << self
        attr_accessor :recorder
      end

      def perform(key:, source:, fire_time_unix:, idempotency_key:)
        self.class.recorder.record(
          key: key,
          source: source,
          fire_time: Time.at(fire_time_unix).utc,
          idempotency_key:
        )
      end
    end

    stub_const('IntegrationSchedulerTestJob', klass)
    klass.recorder = recorder
    klass
  end

  def write_scheduler_config(*jobs)
    FileUtils.rm_rf(@scheduler_tmpdir) if defined?(@scheduler_tmpdir) && @scheduler_tmpdir
    @scheduler_tmpdir = Dir.mktmpdir('kaal-e2e')
    path = File.join(@scheduler_tmpdir, 'scheduler.yml')
    payload = { 'test' => { 'jobs' => jobs } }

    File.write(path, YAML.dump(payload))
    Kaal.configuration.scheduler_config_path = path

    path
  end

  def file_job_definition(key:, source: 'file')
    {
      'key' => key,
      'cron' => '* * * * *',
      'job_class' => 'IntegrationSchedulerTestJob',
      'kwargs' => {
        'key' => '{{key}}',
        'source' => source,
        'fire_time_unix' => '{{fire_time.unix}}',
        'idempotency_key' => '{{idempotency_key}}'
      }
    }
  end

  def build_coordinator(adapter_instance:, registry:)
    configuration = Kaal::Configuration.new
    configuration.backend = adapter_instance
    configuration.tick_interval = 1
    configuration.window_lookback = 30
    configuration.window_lookahead = 0
    configuration.lease_ttl = 31
    configuration.namespace = integration_key_prefix(adapter_label)
    configuration.enable_dispatch_recovery = false
    configuration.logger = Logger.new(StringIO.new)

    Kaal::Coordinator.new(configuration:, registry:)
  end

  private

  def remember_scheduler_definition_key(key)
    keys = scheduler_definition_keys(adapter_label)
    keys << key unless keys.include?(key)
  end

  def scheduler_definition_keys(label)
    @scheduler_definition_keys ||= Hash.new { |hash, key| hash[key] = [] }
    @scheduler_definition_keys[label]
  end
end
