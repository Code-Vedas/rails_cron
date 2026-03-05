# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'

class SchedulerLoaderTestJob < ActiveJob::Base; end

class SchedulerLoaderNotAJob
  def call; end
end

class SchedulerLoaderRailsContext
  def env; end

  def root; end
end

RSpec.describe RailsCron::SchedulerFileLoader do
  let(:configuration) { RailsCron::Configuration.new }
  let(:definition_registry) { RailsCron::Definition::MemoryEngine.new }
  let(:registry) { RailsCron::Registry.new }
  let(:logger) { Logger.new(StringIO.new) }
  let(:tmpdir) { Dir.mktmpdir }
  let(:scheduler_path) { File.join(tmpdir, 'scheduler.yml') }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def write_scheduler(contents)
    File.write(scheduler_path, contents)
  end

  def build_loader(env: 'test')
    configuration.scheduler_config_path = scheduler_path
    rails_context = instance_double(SchedulerLoaderRailsContext, env: env, root: Pathname.new(tmpdir))
    described_class.new(
      configuration: configuration,
      definition_registry: definition_registry,
      registry: registry,
      logger: logger,
      rails_context: rails_context
    )
  end

  it 'loads ERB YAML, merges defaults + env, and persists file definitions' do
    write_scheduler(<<~YAML)
      defaults:
        jobs:
          - key: "job:one"
            cron: "<%= '*/5 * * * *' %>"
            job_class: "SchedulerLoaderTestJob"
            enabled: true
            metadata:
              owner: "ops"
      test:
        jobs:
          - key: "job:two"
            cron: "0 9 * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML

    build_loader.load

    expect(definition_registry.find_definition('job:one')).to include(source: 'file', cron: '*/5 * * * *')
    expect(definition_registry.find_definition('job:two')).to include(source: 'file', cron: '0 9 * * *')
    expect(registry.registered?('job:one')).to be(true)
    expect(registry.registered?('job:two')).to be(true)
  end

  it 'raises for duplicate keys inside YAML' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:dup"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
          - key: "job:dup"
            cron: "0 9 * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Duplicate job keys/)
  end

  it 'raises on unknown placeholders' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:bad_token"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            args:
              - "{{unknown_token}}"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Unknown placeholder/)
  end

  it 'raises when job_class does not inherit from ActiveJob::Base' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:invalid_class"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderNotAJob"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /must inherit from ActiveJob::Base/)
  end

  it 'raises for malformed YAML syntax' do
    write_scheduler("test:\n  jobs:\n    - key: bad\n      cron: '* * * * *'\n      job_class: [\n")

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Failed to parse scheduler YAML/)
  end

  it 'raises for blank key with payload context' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: " "
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Job key cannot be blank:/)
  end

  it 'raises when scheduler_config_path is blank' do
    configuration.scheduler_config_path = ' '
    loader = described_class.new(
      configuration: configuration,
      definition_registry: definition_registry,
      registry: registry,
      logger: logger,
      rails_context: instance_double(SchedulerLoaderRailsContext, env: 'test', root: Pathname.new(tmpdir))
    )

    expect { loader.load }.to raise_error(RailsCron::SchedulerConfigError, /scheduler_config_path cannot be blank/)
  end

  it 'warns without crashing when logger is nil and file is missing' do
    configuration.scheduler_config_path = File.join(tmpdir, 'missing.yml')
    nil_logger_loader = described_class.new(
      configuration: configuration,
      definition_registry: definition_registry,
      registry: registry,
      logger: nil,
      rails_context: instance_double(SchedulerLoaderRailsContext, env: 'test', root: Pathname.new(tmpdir))
    )

    expect { nil_logger_loader.load }.not_to raise_error
  end

  it 'raises when YAML root is not a hash' do
    write_scheduler(<<~YAML)
      - key: "job:array_root"
        cron: "*/5 * * * *"
        job_class: "SchedulerLoaderTestJob"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /root to be a mapping/)
  end

  it 'raises when defaults section is not a mapping' do
    write_scheduler(<<~YAML)
      defaults: 1
      test:
        jobs: []
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /'defaults' section to be a mapping/)
  end

  it 'raises when defaults.jobs is not an array' do
    write_scheduler(<<~YAML)
      defaults:
        jobs: {}
      test:
        jobs: []
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /defaults.jobs/)
  end

  it 'raises when env jobs is not an array' do
    write_scheduler(<<~YAML)
      defaults:
        jobs: []
      test:
        jobs: {}
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /test.jobs/)
  end

  it 'treats YAML false root as empty config and returns no jobs' do
    write_scheduler("false\n")

    expect(build_loader.load).to eq([])
  end

  it 'raises for invalid cron expressions' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:bad_cron"
            cron: "not-a-cron"
            job_class: "SchedulerLoaderTestJob"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Invalid cron expression/)
  end

  it 'raises for non-hash metadata' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:bad_metadata"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            metadata: []
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /metadata must be a mapping/)
  end

  it 'raises for non-array args' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:bad_args"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            args: {}
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /args must be an array/)
  end

  it 'raises for non-hash kwargs' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:bad_kwargs"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            kwargs: []
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /kwargs must be a mapping/)
  end

  it 'raises for non-string queue' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:bad_queue"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            queue: 123
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /queue must be a string/)
  end

  it 'supports enabled false from file config' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:disabled"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            enabled: false
    YAML

    build_loader.load

    expect(definition_registry.find_definition('job:disabled')[:enabled]).to be(false)
  end

  it 'raises when job_class constant is missing' do
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:missing_class"
            cron: "*/5 * * * *"
            job_class: "DoesNotExistJobClass"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Unknown job_class/)
  end

  it 'resolves runtime placeholders during callback execution' do
    allow(SchedulerLoaderTestJob).to receive(:perform_later)
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:runtime"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            args:
              - "{{fire_time.iso8601}}"
              - "prefix-{{idempotency_key}}"
              - 123
            kwargs:
              idempotency_key: "{{idempotency_key}}"
              unix: "{{fire_time.unix}}"
              scheduler_key: "{{key}}"
    YAML

    build_loader.load
    fire_time = Time.zone.parse('2026-03-04 12:00:00 UTC')
    registry.find('job:runtime').enqueue.call(fire_time:, idempotency_key: 'abc-123')

    expect(SchedulerLoaderTestJob).to have_received(:perform_later).with(
      fire_time.iso8601,
      'prefix-abc-123',
      123,
      idempotency_key: 'abc-123',
      unix: fire_time.to_i,
      scheduler_key: 'job:runtime'
    )
  end

  it 'applies queue via ActiveJob#set when queue is configured' do
    set_target = class_double(SchedulerLoaderTestJob, perform_later: true)
    allow(SchedulerLoaderTestJob).to receive(:set).with(queue: 'critical').and_return(set_target)
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:queued"
            cron: "*/5 * * * *"
            job_class: "SchedulerLoaderTestJob"
            queue: "critical"
    YAML

    build_loader.load
    registry.find('job:queued').enqueue.call(fire_time: Time.current, idempotency_key: 'id-1')

    expect(SchedulerLoaderTestJob).to have_received(:set).with(queue: 'critical')
    expect(set_target).to have_received(:perform_later)
  end

  it 'applies conflict policy code_wins by skipping file entry' do
    configuration.scheduler_conflict_policy = :code_wins
    definition_registry.upsert_definition(key: 'job:conflict', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    registry.add(key: 'job:conflict', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] })
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:conflict"
            cron: "0 9 * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML

    build_loader.load

    definition = definition_registry.find_definition('job:conflict')
    expect(definition[:source]).to eq('code')
    expect(definition[:cron]).to eq('* * * * *')
  end

  it 'handles code_wins conflict when logger is nil' do
    configuration.scheduler_conflict_policy = :code_wins
    definition_registry.upsert_definition(key: 'job:conflict_nil_logger', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    registry.add(key: 'job:conflict_nil_logger', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] })
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:conflict_nil_logger"
            cron: "0 9 * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML
    nil_logger_loader = described_class.new(
      configuration: configuration,
      definition_registry: definition_registry,
      registry: registry,
      logger: nil,
      rails_context: instance_double(SchedulerLoaderRailsContext, env: 'test', root: Pathname.new(tmpdir))
    )

    expect { nil_logger_loader.load }.not_to raise_error
  end

  it 'returns true for code_wins conflicts when logger is nil' do
    configuration.scheduler_conflict_policy = :code_wins
    loader = described_class.new(
      configuration: configuration,
      definition_registry: definition_registry,
      registry: registry,
      logger: nil,
      rails_context: instance_double(SchedulerLoaderRailsContext, env: 'test', root: Pathname.new(tmpdir))
    )

    result = loader.send(:skip_due_to_conflict?, key: 'job:one', existing_definition: { source: 'code' })

    expect(result).to be(true)
  end

  it 'raises on conflict when policy is error' do
    definition_registry.upsert_definition(key: 'job:conflict', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    registry.add(key: 'job:conflict', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] })
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:conflict"
            cron: "0 9 * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Scheduler key conflict/)
  end

  it 'applies conflict policy file_wins by replacing definition and callback' do
    configuration.scheduler_conflict_policy = :file_wins
    old_callback = ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] }
    definition_registry.upsert_definition(key: 'job:conflict', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    registry.add(key: 'job:conflict', cron: '* * * * *', enqueue: old_callback)
    allow(SchedulerLoaderTestJob).to receive(:perform_later)
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:conflict"
            cron: "0 9 * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML

    build_loader.load

    definition = definition_registry.find_definition('job:conflict')
    expect(definition[:source]).to eq('file')
    expect(definition[:cron]).to eq('0 9 * * *')

    callback = registry.find('job:conflict').enqueue
    expect(callback).not_to eq(old_callback)
    callback.call(fire_time: Time.current, idempotency_key: 'id-1')
    expect(SchedulerLoaderTestJob).to have_received(:perform_later)
  end

  it 'warns and continues when scheduler file is missing and policy is warn' do
    configuration.scheduler_config_path = File.join(tmpdir, 'missing.yml')
    allow(logger).to receive(:warn)

    result = build_loader.load

    expect(result).to eq([])
    expect(logger).to have_received(:warn).with(/Scheduler file not found/)
  end

  it 'raises when scheduler file is missing and policy is error' do
    configuration.scheduler_missing_file_policy = :error
    configuration.scheduler_config_path = File.join(tmpdir, 'missing.yml')

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Scheduler file not found/)
  end

  it 'raises for unsupported conflict policy when a source conflict exists' do
    configuration.scheduler_conflict_policy = :invalid_policy
    definition_registry.upsert_definition(key: 'job:conflict', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    registry.add(key: 'job:conflict', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) { [fire_time, idempotency_key] })
    write_scheduler(<<~YAML)
      test:
        jobs:
          - key: "job:conflict"
            cron: "0 9 * * *"
            job_class: "SchedulerLoaderTestJob"
    YAML

    expect { build_loader.load }.to raise_error(RailsCron::SchedulerConfigError, /Unsupported scheduler_conflict_policy/)
  end
end
