# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'stringio'

RSpec.describe RailsCron::Configuration do
  subject(:config) { described_class.new }

  let(:adapter) { Object.new }
  let(:logger) { Logger.new(StringIO.new) }
  let(:expected_defaults) do
    {
      tick_interval: 5,
      window_lookback: 120,
      window_lookahead: 0,
      lease_ttl: 60,
      namespace: 'railscron',
      lock_adapter: nil,
      logger: nil,
      time_zone: nil
    }
  end

  describe 'defaults' do
    it 'defaults tick_interval' do
      expect(config.tick_interval).to eq(5)
    end

    it 'defaults window_lookback' do
      expect(config.window_lookback).to eq(120)
    end

    it 'defaults window_lookahead' do
      expect(config.window_lookahead).to eq(0)
    end

    it 'defaults lease_ttl' do
      expect(config.lease_ttl).to eq(60)
    end

    it 'defaults namespace' do
      expect(config.namespace).to eq('railscron')
    end

    it 'defaults lock_adapter' do
      expect(config.lock_adapter).to be_nil
    end

    it 'defaults logger' do
      expect(config.logger).to be_nil
    end

    it 'defaults time_zone' do
      expect(config.time_zone).to be_nil
    end
  end

  describe 'attribute writers' do
    it 'sets tick_interval' do
      config.tick_interval = 10
      expect(config.tick_interval).to eq(10)
    end

    it 'sets window_lookback' do
      config.window_lookback = 250
      expect(config.window_lookback).to eq(250)
    end

    it 'sets window_lookahead' do
      config.window_lookahead = 30
      expect(config.window_lookahead).to eq(30)
    end

    it 'sets lease_ttl' do
      config.lease_ttl = 120
      expect(config.lease_ttl).to eq(120)
    end

    it 'sets namespace' do
      config.namespace = 'custom_namespace'
      expect(config.namespace).to eq('custom_namespace')
    end

    it 'sets lock_adapter' do
      config.lock_adapter = adapter
      expect(config.lock_adapter).to be(adapter)
    end

    it 'sets logger' do
      config.logger = logger
      expect(config.logger).to be(logger)
    end

    it 'sets time_zone' do
      config.time_zone = 'America/Toronto'
      expect(config.time_zone).to eq('America/Toronto')
    end

    it 'allows nil time_zone' do
      config.time_zone = nil
      expect(config.time_zone).to be_nil
    end
  end

  describe '#validate' do
    it 'returns empty array when valid' do
      expect(config.validate).to eq([])
    end

    it 'returns errors when invalid' do
      config.tick_interval = 0
      expect(config.validate.first).to match(/tick_interval/)
    end
  end

  describe 'dynamic accessors' do
    it 'responds to known keys' do
      expect(config.respond_to?(:tick_interval)).to be(true)
    end

    it 'does not respond to unknown keys' do
      expect(config.respond_to?(:unknown_key)).to be(false)
    end

    it 'raises NoMethodError for unknown methods' do
      expect { config.unknown_key }.to raise_error(NoMethodError)
    end

    it 'leaves values unchanged for unknown normalization keys' do
      result = config.send(:normalize_value, :unknown_key, 'raw')
      expect(result).to eq('raw')
    end
  end

  describe '#validate!' do
    it 'returns self when valid' do
      expect(config.validate!).to be(config)
    end

    it 'raises when tick_interval is 0' do
      config.tick_interval = 0
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /tick_interval/)
    end

    it 'raises when tick_interval is negative' do
      config.tick_interval = -5
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /tick_interval/)
    end

    it 'raises when window_lookback is negative' do
      config.window_lookback = -10
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /window_lookback/)
    end

    it 'raises when window_lookahead is negative' do
      config.window_lookahead = -5
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /window_lookahead/)
    end

    it 'raises when lease_ttl is 0' do
      config.lease_ttl = 0
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /lease_ttl/)
    end

    it 'raises when lease_ttl is negative' do
      config.lease_ttl = -15
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /lease_ttl/)
    end

    it 'raises when namespace is empty' do
      config.namespace = ''
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /namespace/)
    end

    it 'raises when namespace is whitespace' do
      config.namespace = '   '
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /namespace/)
    end

    it 'includes multiple errors in the message' do
      config.tick_interval = 0
      config.lease_ttl = 0
      expect { config.validate! }.to raise_error(RailsCron::ConfigurationError, /tick_interval.*lease_ttl|lease_ttl.*tick_interval/)
    end
  end

  describe '#to_h' do
    it 'includes default tick_interval' do
      expect(config.to_h[:tick_interval]).to eq(5)
    end

    it 'includes default window_lookback' do
      expect(config.to_h[:window_lookback]).to eq(120)
    end

    it 'includes default window_lookahead' do
      expect(config.to_h[:window_lookahead]).to eq(0)
    end

    it 'includes default lease_ttl' do
      expect(config.to_h[:lease_ttl]).to eq(60)
    end

    it 'includes default namespace' do
      expect(config.to_h[:namespace]).to eq('railscron')
    end

    it 'includes lock_adapter class name when set' do
      config.lock_adapter = adapter
      expect(config.to_h[:lock_adapter]).to eq('Object')
    end

    it 'includes logger class name when set' do
      config.logger = logger
      expect(config.to_h[:logger]).to eq('Logger')
    end

    it 'includes default time_zone' do
      expect(config.to_h[:time_zone]).to be_nil
    end
  end

  describe 'DEFAULTS' do
    it 'matches expected defaults' do
      expect(described_class::DEFAULTS).to eq(expected_defaults)
    end

    it 'is frozen' do
      expect(described_class::DEFAULTS).to be_frozen
    end
  end
end
