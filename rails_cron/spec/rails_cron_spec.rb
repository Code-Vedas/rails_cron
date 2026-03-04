# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'stringio'
require 'i18n'

RSpec.describe RailsCron do
  let(:adapter) { Object.new }
  let(:logger) { Logger.new(StringIO.new) }

  before do
    # reset_configuration! and reset_registry! automatically invalidate
    # the memoized coordinator, ensuring fresh instances
    described_class.reset_configuration!
    described_class.reset_registry!
  end

  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(described_class.configuration).to be_a(RailsCron::Configuration)
    end

    it 'memoizes the configuration' do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end
  end

  describe '.registry' do
    it 'returns a Registry instance' do
      expect(described_class.registry).to be_a(RailsCron::Registry)
    end

    it 'memoizes the registry' do
      registry1 = described_class.registry
      registry2 = described_class.registry
      expect(registry1).to be(registry2)
    end
  end

  describe '.reset_configuration!' do
    it 'creates a new configuration instance' do
      original_id = described_class.configuration.object_id
      described_class.reset_configuration!
      expect(described_class.configuration.object_id).not_to eq(original_id)
    end

    it 'restores default values' do
      described_class.configuration.tick_interval = 10
      described_class.reset_configuration!
      expect(described_class.configuration.tick_interval).to eq(5)
    end
  end

  describe '.reset_registry!' do
    it 'creates a new registry instance' do
      original_id = described_class.registry.object_id
      described_class.reset_registry!
      expect(described_class.registry.object_id).not_to eq(original_id)
    end

    it 'clears registered entries' do
      described_class.register(key: 'job:one', cron: '0 9 * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      expect { described_class.reset_registry! }.to change { described_class.registry.size }.from(1).to(0)
    end

    it 'clears fallback definition registry when present' do
      fallback_registry = instance_double(RailsCron::Definition::MemoryEngine)
      allow(fallback_registry).to receive(:clear)
      described_class.instance_variable_set(:@definition_registry, fallback_registry)

      described_class.reset_registry!

      expect(fallback_registry).to have_received(:clear)
    end

    it 'does not call clear when definition registry is nil' do
      described_class.instance_variable_set(:@definition_registry, nil)

      expect { described_class.reset_registry! }.not_to raise_error
    end
  end

  describe '.configure' do
    it 'yields the configuration' do
      expect { |block| described_class.configure(&block) }.to yield_with_args(described_class.configuration)
    end

    it 'applies configuration changes' do
      described_class.configure { |config| config.tick_interval = 10 }
      expect(described_class.configuration.tick_interval).to eq(10)
    end

    it 'does not raise without a block' do
      expect { described_class.configure }.not_to raise_error
    end
  end

  describe 'configuration readers' do
    {
      tick_interval: 12,
      window_lookback: 100,
      window_lookahead: 5,
      lease_ttl: 90,
      namespace: 'custom',
      time_zone: 'UTC'
    }.each do |attr, value|
      it "reads #{attr}" do
        described_class.configuration.public_send("#{attr}=", value)
        expect(described_class.public_send(attr)).to eq(value)
      end
    end

    it 'reads backend' do
      described_class.configuration.backend = adapter
      expect(described_class.backend).to be(adapter)
    end

    it 'reads logger' do
      described_class.configuration.logger = logger
      expect(described_class.logger).to be(logger)
    end
  end

  describe 'configuration writers' do
    {
      tick_interval: 8,
      window_lookback: 200,
      window_lookahead: 10,
      lease_ttl: 70,
      namespace: 'acme',
      time_zone: 'America/Toronto'
    }.each do |attr, value|
      it "writes #{attr}" do
        described_class.public_send("#{attr}=", value)
        expect(described_class.configuration.public_send(attr)).to eq(value)
      end
    end

    it 'writes backend' do
      described_class.backend = adapter
      expect(described_class.configuration.backend).to be(adapter)
    end

    it 'writes logger' do
      described_class.logger = logger
      expect(described_class.configuration.logger).to be(logger)
    end
  end

  describe '.validate' do
    it 'returns validation errors' do
      described_class.configuration.tick_interval = 0
      expect(described_class.validate.first).to match(/tick_interval/)
    end
  end

  describe '.validate!' do
    it 'raises when invalid' do
      described_class.configuration.tick_interval = 0
      expect { described_class.validate! }.to raise_error(RailsCron::ConfigurationError, /tick_interval/)
    end
  end

  describe '.register' do
    it 'returns a registry entry' do
      entry = described_class.register(
        key: 'reports:daily',
        cron: '0 9 * * *',
        enqueue: ->(fire_time:, idempotency_key:) {}
      )
      expect(entry).to be_a(RailsCron::Registry::Entry)
    end

    it 'adds entry to the registry' do
      register = lambda do
        described_class.register(
          key: 'job:one',
          cron: '0 9 * * *',
          enqueue: ->(fire_time:, idempotency_key:) {}
        )
      end

      expect(&register).to change(described_class.registry, :size).from(0).to(1)
    end

    it 'raises RegistryError when key already exists' do
      described_class.register(key: 'job:one', cron: '* * * * *', enqueue: ->(fire_time:, idempotency_key:) {})

      expect do
        described_class.register(key: 'job:one', cron: '0 9 * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      end.to raise_error(RailsCron::RegistryError, /already registered/)
    end

    it 'rolls back definition when registry add fails' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:find_definition).and_return(nil)
      allow(definition_registry).to receive(:upsert_definition)
      allow(definition_registry).to receive(:remove_definition)
      allow(described_class.registry).to receive(:add).and_raise(StandardError, 'registry failure')

      expect do
        described_class.register(
          key: 'job:rollback',
          cron: '0 9 * * *',
          enqueue: ->(fire_time:, idempotency_key:) {}
        )
      end.to raise_error(StandardError, 'registry failure')

      expect(definition_registry).to have_received(:remove_definition).with('job:rollback')
    end

    it 'restores an existing persisted definition when registry add fails' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      existing_definition = {
        key: 'job:existing',
        cron: '0 8 * * *',
        enabled: false,
        source: 'api',
        metadata: { owner: 'ops' }
      }

      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:find_definition).with('job:existing').and_return(existing_definition)
      allow(definition_registry).to receive(:upsert_definition)
      allow(definition_registry).to receive(:remove_definition)
      allow(described_class.registry).to receive(:add).and_raise(StandardError, 'registry failure')

      expect do
        described_class.register(
          key: 'job:existing',
          cron: '0 9 * * *',
          enqueue: ->(fire_time:, idempotency_key:) {}
        )
      end.to raise_error(StandardError, 'registry failure')

      expect(definition_registry).to have_received(:upsert_definition).with(
        key: 'job:existing',
        cron: '0 8 * * *',
        enabled: false,
        source: 'api',
        metadata: { owner: 'ops' }
      )
      expect(definition_registry).not_to have_received(:remove_definition)
    end

    it 'does not remove a newly persisted definition when the key becomes registered before rollback' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:find_definition).and_return(nil)
      allow(definition_registry).to receive(:upsert_definition)
      allow(definition_registry).to receive(:remove_definition)
      allow(described_class.registry).to receive(:add).and_raise(StandardError, 'registry failure')
      allow(described_class.registry).to receive(:registered?).with('job:race').and_return(false, true)

      expect do
        described_class.register(
          key: 'job:race',
          cron: '0 9 * * *',
          enqueue: ->(fire_time:, idempotency_key:) {}
        )
      end.to raise_error(StandardError, 'registry failure')

      expect(definition_registry).not_to have_received(:remove_definition)
    end

    it 'logs rollback failure but re-raises the original registry add error' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:find_definition).and_return(nil)
      allow(definition_registry).to receive(:upsert_definition)
      allow(definition_registry).to receive(:remove_definition).and_raise(StandardError, 'rollback failure')
      allow(described_class.registry).to receive(:add).and_raise(StandardError, 'registry failure')
      described_class.configuration.logger = logger

      expect do
        described_class.register(
          key: 'job:rollback',
          cron: '0 9 * * *',
          enqueue: ->(fire_time:, idempotency_key:) {}
        )
      end.to raise_error(StandardError, 'registry failure')

      expect(logger.instance_variable_get(:@logdev).dev.string).to include(
        'Failed to rollback persisted definition for job:rollback: rollback failure'
      )
    end

    it 're-raises the original registry add error when rollback fails and logger is nil' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:find_definition).and_return(nil)
      allow(definition_registry).to receive(:upsert_definition)
      allow(definition_registry).to receive(:remove_definition).and_raise(StandardError, 'rollback failure')
      allow(described_class.registry).to receive(:add).and_raise(StandardError, 'registry failure')
      described_class.configuration.logger = nil

      expect do
        described_class.register(
          key: 'job:rollback',
          cron: '0 9 * * *',
          enqueue: ->(fire_time:, idempotency_key:) {}
        )
      end.to raise_error(StandardError, 'registry failure')
    end

    it 'does not remove persisted definition when upsert fails' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:upsert_definition).and_raise(StandardError, 'upsert failure')
      allow(definition_registry).to receive(:find_definition).and_return(nil)
      allow(definition_registry).to receive(:remove_definition)

      expect do
        described_class.register(
          key: 'job:existing',
          cron: '0 9 * * *',
          enqueue: ->(fire_time:, idempotency_key:) {}
        )
      end.to raise_error(StandardError, 'upsert failure')

      expect(definition_registry).not_to have_received(:remove_definition)
    end

    it 'preserves existing persisted attributes when re-registering a definition' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      existing_definition = {
        key: 'job:managed',
        cron: '0 8 * * *',
        enabled: false,
        source: 'api',
        metadata: { owner: 'ops' }
      }

      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:find_definition).with('job:managed').and_return(existing_definition)
      allow(definition_registry).to receive(:upsert_definition)

      described_class.register(
        key: 'job:managed',
        cron: '0 9 * * *',
        enqueue: ->(fire_time:, idempotency_key:) {}
      )

      expect(definition_registry).to have_received(:upsert_definition).with(
        key: 'job:managed',
        cron: '0 9 * * *',
        enabled: false,
        source: 'api',
        metadata: { owner: 'ops' }
      )
    end
  end

  describe '.rollback_registered_definition' do
    it 'is a private singleton method' do
      expect(described_class.private_methods).to include(:rollback_registered_definition)
    end
  end

  describe '.unregister' do
    it 'removes the entry from the registry' do
      described_class.register(key: 'job:one', cron: '0 9 * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      expect { described_class.unregister(key: 'job:one') }.to change(described_class.registry, :size).from(1).to(0)
    end

    it 'returns nil when entry not found' do
      expect(described_class.unregister(key: 'missing:job')).to be_nil
    end
  end

  describe '.registered' do
    it 'returns all registered entries' do
      described_class.register(key: 'job:one', cron: '0 9 * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      described_class.register(key: 'job:two', cron: '0 10 * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      expect(described_class.registered.map(&:key)).to contain_exactly('job:one', 'job:two')
    end

    it 'returns empty array when no entries' do
      expect(described_class.registered).to eq([])
    end

    it 'returns definitions even when callback is missing from in-memory registry' do
      described_class.definition_registry.upsert_definition(
        key: 'job:definition-only',
        cron: '0 11 * * *',
        enabled: true,
        source: 'code',
        metadata: {}
      )

      result = described_class.registered

      expect(result.size).to eq(1)
      expect(result.first.key).to eq('job:definition-only')
      expect(result.first.enqueue).to be_nil
    end
  end

  describe '.registered?' do
    it 'returns true when key is registered' do
      described_class.register(key: 'job:one', cron: '0 9 * * *', enqueue: ->(fire_time:, idempotency_key:) {})
      expect(described_class.registered?(key: 'job:one')).to be(true)
    end

    it 'returns false when key is not registered' do
      expect(described_class.registered?(key: 'job:missing')).to be(false)
    end
  end

  describe '.enable/.disable' do
    it 'delegates to definition registry enable_definition' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:enable_definition).with('job:one').and_return({ key: 'job:one', enabled: true })

      result = described_class.enable(key: 'job:one')

      expect(result).to eq({ key: 'job:one', enabled: true })
      expect(definition_registry).to have_received(:enable_definition).with('job:one')
    end

    it 'delegates to definition registry disable_definition' do
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(described_class).to receive(:definition_registry).and_return(definition_registry)
      allow(definition_registry).to receive(:disable_definition).with('job:one').and_return({ key: 'job:one', enabled: false })

      result = described_class.disable(key: 'job:one')

      expect(result).to eq({ key: 'job:one', enabled: false })
      expect(definition_registry).to have_received(:disable_definition).with('job:one')
    end
  end

  describe '.definition_registry' do
    it 'uses backend provided definition registry when present' do
      backend = instance_double(RailsCron::Backend::Adapter)
      definition_registry = instance_double(RailsCron::Definition::Registry)
      allow(backend).to receive(:definition_registry).and_return(definition_registry)
      described_class.configuration.backend = backend

      expect(described_class.definition_registry).to be(definition_registry)
    end

    it 'falls back to in-memory definition registry when backend returns nil' do
      backend = instance_double(RailsCron::Backend::Adapter)
      allow(backend).to receive(:definition_registry).and_return(nil)
      described_class.configuration.backend = backend

      expect(described_class.definition_registry).to be_a(RailsCron::Definition::MemoryEngine)
    end

    it 'falls back to in-memory definition registry when backend method is missing' do
      backend = Class.new do
        def definition_registry
          raise NoMethodError
        end
      end.new
      described_class.configuration.backend = backend

      expect(described_class.definition_registry).to be_a(RailsCron::Definition::MemoryEngine)
    end
  end

  describe '.coordinator' do
    it 'returns a Coordinator instance' do
      expect(described_class.coordinator).to be_a(RailsCron::Coordinator)
    end

    it 'memoizes the coordinator' do
      coordinator1 = described_class.coordinator
      coordinator2 = described_class.coordinator
      expect(coordinator1).to be(coordinator2)
    end
  end

  describe '.reset_coordinator!' do
    it 'resets the coordinator and returns a new instance' do
      original_coordinator = described_class.coordinator
      original_id = original_coordinator.object_id

      new_coordinator = described_class.reset_coordinator!

      expect(new_coordinator.object_id).not_to eq(original_id)
      expect(new_coordinator).to be_a(RailsCron::Coordinator)
    end

    it 'stops a running coordinator before resetting' do
      coordinator = described_class.coordinator
      coordinator.start!

      expect(coordinator.running?).to be true

      new_coordinator = described_class.reset_coordinator!

      expect(coordinator.running?).to be false
      expect(new_coordinator).not_to eq(coordinator)
    end

    it 'does not error when coordinator is not running' do
      coordinator = described_class.coordinator
      expect(coordinator.running?).to be false

      expect { described_class.reset_coordinator! }.not_to raise_error
    end

    it 'handles nil coordinator gracefully' do
      # Ensure @coordinator is nil without calling coordinator method
      described_class.instance_variable_set(:@coordinator, nil)

      expect { described_class.reset_coordinator! }.not_to raise_error
      expect(described_class.coordinator).to be_a(RailsCron::Coordinator)
    end

    it 'raises error when stop! times out' do
      coordinator = described_class.coordinator
      coordinator.start!

      # Stub stop! to return false (timeout)
      allow(coordinator).to receive(:stop!).and_return(false)

      expect { described_class.reset_coordinator! }.to raise_error(RuntimeError, /Failed to stop coordinator/)
    end
  end

  describe '.start!' do
    it 'starts the coordinator' do
      coordinator = described_class.coordinator
      allow(coordinator).to receive(:start!)

      described_class.start!

      expect(coordinator).to have_received(:start!)
    end
  end

  describe '.stop!' do
    it 'stops the coordinator with default timeout' do
      coordinator = described_class.coordinator
      allow(coordinator).to receive(:stop!)

      described_class.stop!

      expect(coordinator).to have_received(:stop!).with(timeout: 30)
    end

    it 'stops the coordinator with custom timeout' do
      coordinator = described_class.coordinator
      allow(coordinator).to receive(:stop!)

      described_class.stop!(timeout: 60)

      expect(coordinator).to have_received(:stop!).with(timeout: 60)
    end
  end

  describe '.restart!' do
    it 'restarts the coordinator' do
      coordinator = described_class.coordinator
      allow(coordinator).to receive(:restart!)

      described_class.restart!

      expect(coordinator).to have_received(:restart!)
    end
  end

  describe '.tick!' do
    it 'executes a single tick on the coordinator' do
      coordinator = described_class.coordinator
      allow(coordinator).to receive(:tick!)

      described_class.tick!

      expect(coordinator).to have_received(:tick!)
    end
  end

  describe '.running?' do
    it 'returns the running status from coordinator' do
      coordinator = described_class.coordinator
      allow(coordinator).to receive(:running?).and_return(true)

      expect(described_class.running?).to be(true)
    end

    it 'returns false when coordinator is not running' do
      coordinator = described_class.coordinator
      allow(coordinator).to receive(:running?).and_return(false)

      expect(described_class.running?).to be(false)
    end
  end

  describe '.with_idempotency' do
    it 'generates an idempotency key with default namespace' do
      fire_time = Time.at(1_234_567_890)
      result = described_class.with_idempotency('reports:daily', fire_time) do |idempotency_key|
        idempotency_key
      end

      expect(result).to eq('railscron-reports:daily-1234567890')
    end

    it 'generates an idempotency key with custom namespace' do
      described_class.configure do |config|
        config.namespace = 'myapp'
      end

      fire_time = Time.at(1_234_567_890)
      result = described_class.with_idempotency('reports:daily', fire_time) do |idempotency_key|
        idempotency_key
      end

      expect(result).to eq('myapp-reports:daily-1234567890')
    end

    it 'yields the idempotency key to the block' do
      fire_time = Time.current
      yielded_key = nil

      described_class.with_idempotency('test:job', fire_time) do |key|
        yielded_key = key
      end

      expect(yielded_key).to match(/^railscron-test:job-\d+$/)
    end

    it 'returns the result of the block' do
      fire_time = Time.current
      result = described_class.with_idempotency('sync:data', fire_time) do |_key|
        'custom_result'
      end

      expect(result).to eq('custom_result')
    end

    it 'handles complex cron keys with multiple colons' do
      described_class.configure do |config|
        config.namespace = 'custom'
      end

      fire_time = Time.at(1_609_459_200)
      result = described_class.with_idempotency('reports:weekly:summary', fire_time) do |key|
        key
      end

      expect(result).to eq('custom-reports:weekly:summary-1609459200')
    end

    it 'generates deterministic keys for the same inputs' do
      fire_time = Time.at(1_234_567_890)

      key1 = described_class.with_idempotency('reports:daily', fire_time) { |k| k }
      key2 = described_class.with_idempotency('reports:daily', fire_time) { |k| k }

      expect(key1).to eq(key2)
    end

    it 'generates different keys for different cron keys' do
      fire_time = Time.at(1_234_567_890)

      key1 = described_class.with_idempotency('reports:daily', fire_time) { |k| k }
      key2 = described_class.with_idempotency('reports:weekly', fire_time) { |k| k }

      expect(key1).not_to eq(key2)
    end

    it 'generates different keys for different fire times' do
      key1 = described_class.with_idempotency('reports:daily', Time.at(1_234_567_890)) { |k| k }
      key2 = described_class.with_idempotency('reports:daily', Time.at(1_234_567_891)) { |k| k }

      expect(key1).not_to eq(key2)
    end

    it 'allows the block to perform operations with the idempotency key' do
      fire_time = Time.current
      operations = []

      described_class.with_idempotency('test:job', fire_time) do |idempotency_key|
        operations << idempotency_key
        operations << 'processed'
      end

      expect(operations).to include(an_instance_of(String))
      expect(operations).to include('processed')
    end

    it 'raises ArgumentError when called without a block' do
      fire_time = Time.current

      expect do
        described_class.with_idempotency('test:job', fire_time)
      end.to raise_error(ArgumentError, 'block required')
    end
  end

  describe '.dispatched?' do
    it 'returns false when adapter is nil' do
      described_class.configuration.backend = nil

      result = described_class.dispatched?('test:job', Time.current)
      expect(result).to be(false)
    end

    it 'returns false when adapter does not have dispatch_registry' do
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, respond_to?: false)
      described_class.configuration.backend = adapter

      result = described_class.dispatched?('test:job', Time.current)
      expect(result).to be(false)
    end

    it 'returns false when registry returns nil' do
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, dispatch_registry: nil)
      described_class.configuration.backend = adapter

      result = described_class.dispatched?('test:job', Time.current)
      expect(result).to be(false)
    end

    it 'returns the result from dispatch_registry.dispatched?' do
      registry = instance_double(RailsCron::Dispatch::Registry)
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, dispatch_registry: registry)
      fire_time = Time.current

      allow(registry).to receive(:dispatched?).with('test:job', fire_time).and_return(true)
      described_class.configuration.backend = adapter

      result = described_class.dispatched?('test:job', fire_time)
      expect(result).to be(true)
    end

    it 'returns false when registry.dispatched? returns false' do
      registry = instance_double(RailsCron::Dispatch::Registry)
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, dispatch_registry: registry)
      fire_time = Time.current

      allow(registry).to receive(:dispatched?).with('test:job', fire_time).and_return(false)
      described_class.configuration.backend = adapter

      result = described_class.dispatched?('test:job', fire_time)
      expect(result).to be(false)
    end

    it 'returns false and logs when adapter.dispatch_registry raises' do
      logger = instance_double(Logger, warn: nil)
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, respond_to?: true)
      fire_time = Time.current

      allow(adapter).to receive(:dispatch_registry).and_raise(StandardError, 'backend error')
      described_class.configuration.backend = adapter
      described_class.configuration.logger = logger

      result = described_class.dispatched?('test:job', fire_time)
      expect(result).to be(false)
      expect(logger).to have_received(:warn).with(/Error checking dispatch status for test:job: backend error/)
    end

    it 'returns false and logs when registry.dispatched? raises' do
      logger = instance_double(Logger, warn: nil)
      registry = instance_double(RailsCron::Dispatch::Registry)
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, dispatch_registry: registry)
      fire_time = Time.current

      allow(registry).to receive(:dispatched?).and_raise(StandardError, 'database error')
      described_class.configuration.backend = adapter
      described_class.configuration.logger = logger

      result = described_class.dispatched?('test:job', fire_time)
      expect(result).to be(false)
      expect(logger).to have_received(:warn).with(/Error checking dispatch status for test:job: database error/)
    end

    it 'returns false when logger is nil' do
      registry = instance_double(RailsCron::Dispatch::Registry)
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, dispatch_registry: registry)
      fire_time = Time.current

      allow(registry).to receive(:dispatched?).and_raise(StandardError, 'error')
      described_class.configuration.backend = adapter
      described_class.configuration.logger = nil

      result = described_class.dispatched?('test:job', fire_time)
      expect(result).to be(false)
    end
  end

  describe '.dispatch_log_registry' do
    it 'returns nil when adapter is nil' do
      described_class.configuration.backend = nil

      result = described_class.dispatch_log_registry
      expect(result).to be_nil
    end

    it 'returns nil when adapter does not have dispatch_registry' do
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, respond_to?: false)
      described_class.configuration.backend = adapter

      result = described_class.dispatch_log_registry
      expect(result).to be_nil
    end

    it 'returns nil when dispatch_registry returns nil' do
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, dispatch_registry: nil)
      described_class.configuration.backend = adapter

      result = described_class.dispatch_log_registry
      expect(result).to be_nil
    end

    it 'returns the dispatch_registry from the adapter' do
      registry = instance_double(RailsCron::Dispatch::Registry)
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, dispatch_registry: registry)
      described_class.configuration.backend = adapter

      result = described_class.dispatch_log_registry
      expect(result).to eq(registry)
    end

    it 'returns nil and logs when adapter.dispatch_registry raises' do
      logger = instance_double(Logger, warn: nil)
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, respond_to?: true)

      allow(adapter).to receive(:dispatch_registry).and_raise(StandardError, 'backend error')
      described_class.configuration.backend = adapter
      described_class.configuration.logger = logger

      result = described_class.dispatch_log_registry
      expect(result).to be_nil
      expect(logger).to have_received(:warn).with(/Error accessing dispatch registry: backend error/)
    end

    it 'returns nil when logger is nil' do
      adapter = instance_double(RailsCron::Backend::MemoryAdapter, respond_to?: true)

      allow(adapter).to receive(:dispatch_registry).and_raise(StandardError, 'database error')
      described_class.configuration.backend = adapter
      described_class.configuration.logger = nil

      result = described_class.dispatch_log_registry
      expect(result).to be_nil
    end
  end

  describe '.valid?' do
    it 'returns true for valid 5-field cron expressions' do
      expect(described_class.valid?('*/5 * * * *')).to be(true)
    end

    it 'returns true for supported macros' do
      expect(described_class.valid?('@daily')).to be(true)
    end

    it 'returns false for invalid cron expressions' do
      expect(described_class.valid?('61 * * * *')).to be(false)
    end

    it 'returns false when expression has more than 5 fields' do
      expect(described_class.valid?('* * * * * *')).to be(false)
    end

    it 'returns false for empty expressions' do
      expect(described_class.valid?('   ')).to be(false)
    end

    it 'returns false when expression normalization raises' do
      invalid_expression = Object.new
      allow(invalid_expression).to receive(:to_s).and_raise(StandardError, 'boom')

      expect(described_class.valid?(invalid_expression)).to be(false)
    end
  end

  describe '.simplify' do
    it 'simplifies a matching cron expression to a canonical macro' do
      expect(described_class.simplify('0 0 * * *')).to eq('@daily')
    end

    it 'simplifies weekly expressions to @weekly' do
      expect(described_class.simplify('0 0 * * 0')).to eq('@weekly')
      expect(described_class.simplify('0 0 * * 7')).to eq('@weekly')
    end

    it 'returns canonical macro for macro aliases' do
      expect(described_class.simplify('@midnight')).to eq('@daily')
    end

    it 'returns normalized expression when no macro applies' do
      expect(described_class.simplify(' 15  9 * * 1 ')).to eq('15 9 * * 1')
    end

    it 'raises a helpful error for invalid expressions' do
      expect do
        described_class.simplify('not-a-cron')
      end.to raise_error(ArgumentError, %r{Invalid cron expression 'not-a-cron'.*Examples: '\*/5 \* \* \* \*', '@daily'.})
    end

    it 'raises a helpful error for empty expressions' do
      expect do
        described_class.simplify('   ')
      end.to raise_error(ArgumentError, /Invalid cron expression '<empty>'/)
    end

    it 'raises unsupported macro errors for unknown macros' do
      expect do
        described_class.simplify('@every_5m')
      end.to raise_error(ArgumentError, /Unsupported cron macro '@every_5m'/)
    end

    it 'raises invalid-expression errors when normalization fails' do
      invalid_expression = Object.new
      allow(invalid_expression).to receive(:to_s).and_raise(StandardError, 'boom')

      expect do
        described_class.simplify(invalid_expression)
      end.to raise_error(ArgumentError, /Invalid cron expression '<empty>'/)
    end
  end

  describe '.lint' do
    it 'returns no warnings for valid expressions' do
      expect(described_class.lint('0 9 * * 1')).to eq([])
    end

    it 'returns no warnings for supported macros' do
      expect(described_class.lint('@weekly')).to eq([])
    end

    it 'returns helpful error for empty expressions' do
      expect(described_class.lint('')).to eq(["Invalid cron expression '<empty>'. Examples: '*/5 * * * *', '@daily'."])
    end

    it 'returns field count errors for non-5-field expressions' do
      result = described_class.lint('* * * * * *')
      expect(result.first).to match(/Expected 5 fields/)
    end

    it 'returns step out-of-range warnings' do
      result = described_class.lint('*/61 * * * *')
      expect(result).to include("minute step '61' is out of range. Allowed step: 1-60.")
    end

    it 'accepts valid star steps' do
      expect(described_class.lint('*/2 * * * *')).to eq([])
    end

    it 'returns helpful error for unsupported macros' do
      result = described_class.lint('@every_5m')
      expect(result.first).to match(/Unsupported cron macro '@every_5m'/)
    end

    it 'accepts valid ranges and step segments' do
      expect(described_class.lint('1-5 * * * *')).to eq([])
      expect(described_class.lint('5/2 * * * *')).to eq([])
    end

    it 'flags out-of-range values in ranges' do
      result = described_class.lint('99-100 * * * *')
      expect(result).to include("minute range '99-100' contains an out-of-range value.")
    end

    it 'flags out-of-range single values' do
      result = described_class.lint('99 * * * *')
      expect(result).to include("minute value '99' is out of range (0-59).")
    end

    it 'flags reversed ranges' do
      result = described_class.lint('10-5 * * * *')
      expect(result).to include("minute range '10-5' has start greater than end.")
    end

    it 'accepts valid range steps' do
      expect(described_class.lint('1-5/2 * * * *')).to eq([])
    end

    it 'flags range steps outside the range span' do
      result = described_class.lint('1-3/5 * * * *')
      expect(result).to include("minute step '5' is out of range for range '1-3/5'. Allowed step: 1-3.")
    end

    it 'flags base step with out-of-range base values' do
      result = described_class.lint('foo/2 * * * *')
      expect(result).to include("minute value 'foo/2' contains an out-of-range value.")
    end

    it 'flags base step with non-positive step values' do
      result = described_class.lint('5/0 * * * *')
      expect(result).to include("minute step '0' is out of range. Allowed step: 1 or greater.")
    end

    it 'supports named month and day tokens' do
      expect(described_class.lint('0 9 * jan mon')).to eq([])
    end

    it 'returns invalid-expression warnings when normalization fails' do
      invalid_expression = Object.new
      allow(invalid_expression).to receive(:to_s).and_raise(StandardError, 'boom')

      expect(described_class.lint(invalid_expression)).to eq(["Invalid cron expression '<empty>'. Examples: '*/5 * * * *', '@daily'."])
    end
  end

  describe '.to_human' do
    around do |example|
      original_locale = I18n.locale
      original_available_locales = I18n.available_locales
      I18n.available_locales = (original_available_locales + [:zz]).uniq
      I18n.backend.store_translations(:zz, {
                                        rails_cron: {
                                          every: 'cada',
                                          at: 'a las',
                                          and: 'y',
                                          time: {
                                            minute: 'minuto',
                                            minutes: 'minutos',
                                            hour: 'hora',
                                            hours: 'horas',
                                            day: 'dia',
                                            days: 'dias',
                                            week: 'semana',
                                            weeks: 'semanas',
                                            month: 'mes',
                                            months: 'meses'
                                          },
                                          weekdays: {
                                            '0' => 'domingo',
                                            '1' => 'lunes',
                                            '2' => 'martes',
                                            '3' => 'miercoles',
                                            '4' => 'jueves',
                                            '5' => 'viernes',
                                            '6' => 'sabado'
                                          },
                                          months: {
                                            '1' => 'enero',
                                            '2' => 'febrero',
                                            '3' => 'marzo',
                                            '4' => 'abril',
                                            '5' => 'mayo',
                                            '6' => 'junio',
                                            '7' => 'julio',
                                            '8' => 'agosto',
                                            '9' => 'septiembre',
                                            '10' => 'octubre',
                                            '11' => 'noviembre',
                                            '12' => 'diciembre'
                                          },
                                          phrases: {
                                            daily: 'Diario',
                                            weekly: 'Semanal',
                                            monthly: 'Mensual',
                                            hourly: 'Cada hora',
                                            yearly: 'Anual',
                                            at_time: ['A las ', '%{', 'time', '}'].join,
                                            every_interval: ['Cada ', '%{', 'count', '}', ' ', '%{', 'unit', '}'].join,
                                            cron_expression: ['Cron: ', '%{', 'expression', '}'].join
                                          }
                                        }
                                      })
      begin
        example.run
      ensure
        I18n.locale = original_locale
        I18n.available_locales = original_available_locales
      end
    end

    it 'humanizes weekly fixed-time expressions' do
      expect(described_class.to_human('0 9 * * 1')).to eq('At 09:00 every Monday')
    end

    it 'humanizes predefined macros' do
      expect(described_class.to_human('@daily')).to eq('Daily')
    end

    it 'uses current I18n.locale when locale is nil' do
      I18n.locale = :zz
      expect(described_class.to_human('0 9 * * 1')).to eq('A las 09:00 cada lunes')
    end

    it 'uses locale override when provided' do
      I18n.locale = :en
      expect(described_class.to_human('0 9 * * 1', locale: :zz)).to eq('A las 09:00 cada lunes')
    end

    it 'humanizes every-minute intervals' do
      expect(described_class.to_human('*/5 * * * *')).to eq('Every 5 minutes')
    end

    it 'uses singular units for 1-minute intervals' do
      unit = RailsCron::CronHumanizer.send(:interval_unit, 1, singular: 'minute', plural: 'minutes')
      expect(unit).to eq('minute')
    end

    it 'humanizes fixed-time daily expressions' do
      expect(described_class.to_human('30 10 * * *')).to eq('At 10:30 every day')
    end

    it 'humanizes 5-field expressions that map to canonical macros' do
      expect(described_class.to_human('0 0 * * *')).to eq('Daily')
    end

    it 'treats weekday 7 as Sunday' do
      expect(described_class.to_human('0 9 * * 7')).to eq('At 09:00 every Sunday')
    end

    it 'falls back to canonical cron text for unsupported complex expressions' do
      expect(described_class.to_human('15 10 2 3 *')).to eq('Cron: 15 10 2 3 *')
    end

    it 'falls back to canonical cron text for multi-weekday ranges' do
      expect(described_class.to_human('0 9 * * 1-2')).to eq('Cron: 0 9 * * 1,2')
    end

    it 'falls back when minute intervals are irregular' do
      expect(described_class.to_human('0,10,25 * * * *')).to eq('Cron: 0,10,25 * * * *')
    end

    it 'falls back when macro phrase mapping is unavailable' do
      stub_const('RailsCron::CronHumanizer::MACRO_PHRASES', {})
      expect(described_class.to_human('@daily')).to eq('Cron: @daily')
    end

    it 'falls back when the humanized phrase is blank' do
      allow(RailsCron::CronHumanizer).to receive(:humanize_expression).and_return('  ')
      expect(described_class.to_human('0 9 * * 1')).to eq('Cron: 0 9 * * 1')
    end

    it 'does not swallow unexpected parser errors' do
      allow(Fugit).to receive(:parse_cron).with('0 1 * * *').and_raise(StandardError, 'boom')

      expect do
        described_class.to_human('0 1 * * *')
      end.to raise_error(StandardError, 'boom')
    end

    it 'raises invalid-expression errors for empty input' do
      expect do
        described_class.to_human('   ')
      end.to raise_error(ArgumentError, /Invalid cron expression '<empty>'/)
    end

    it 'raises helpful error for invalid cron expressions' do
      expect do
        described_class.to_human('invalid')
      end.to raise_error(ArgumentError, /Invalid cron expression 'invalid'/)
    end

    it 'raises unsupported macro errors for unknown macros' do
      expect do
        described_class.to_human('@every_5m')
      end.to raise_error(ArgumentError, /Unsupported cron macro '@every_5m'/)
    end

    it 'raises invalid-expression errors when normalization fails' do
      invalid_expression = Object.new
      allow(invalid_expression).to receive(:to_s).and_raise(StandardError, 'boom')

      expect do
        described_class.to_human(invalid_expression)
      end.to raise_error(ArgumentError, /Invalid cron expression '<empty>'/)
    end

    it 'returns fallback text for non-interval minute-only schedules' do
      expect(described_class.to_human('5 * * * *')).to eq('Cron: 5 * * * *')
    end

    it 'covers helper edge branches for interval and weekday extraction' do
      expect(RailsCron::CronHumanizer.send(:derive_interval, [5, 10, 15])).to be_nil
      expect(RailsCron::CronHumanizer.send(:derive_interval, [0, 0, 5])).to be_nil
      expect(RailsCron::CronHumanizer.send(:derive_interval, [0, 0, 0])).to be_nil
      expect(RailsCron::CronHumanizer.send(:derive_interval, [0, 10, 20])).to be_nil

      expect(RailsCron::CronHumanizer.send(:extract_weekday, [1])).to eq(1)
      expect(RailsCron::CronHumanizer.send(:extract_weekday, ['mon'])).to be_nil
      expect(RailsCron::CronHumanizer.send(:extract_weekday, [['mon']])).to be_nil

      expect(RailsCron::CronHumanizer.send(:weekday_name, 7)).to eq('Sunday')
    end
  end
end
