# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'stringio'

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

    it 'reads lock_adapter' do
      described_class.configuration.lock_adapter = adapter
      expect(described_class.lock_adapter).to be(adapter)
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

    it 'writes lock_adapter' do
      described_class.lock_adapter = adapter
      expect(described_class.configuration.lock_adapter).to be(adapter)
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
end
