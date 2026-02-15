# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe RailsCron do
  let(:adapter) { Object.new }
  let(:logger) { Logger.new(StringIO.new) }

  before do
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
end
