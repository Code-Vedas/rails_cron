# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Dispatch::RedisEngine do
  subject(:engine) { described_class.new(redis_client, namespace: 'test', ttl: 3600) }

  let(:redis_client) { instance_double(Redis) }

  describe '#initialize' do
    it 'sets redis client, namespace, and ttl' do
      engine = described_class.new(redis_client, namespace: 'myapp', ttl: 7200)

      expect(engine.instance_variable_get(:@redis)).to eq(redis_client)
      expect(engine.instance_variable_get(:@namespace)).to eq('myapp')
      expect(engine.instance_variable_get(:@ttl)).to eq(7200)
    end

    it 'uses default namespace and ttl' do
      engine = described_class.new(redis_client)

      expect(engine.instance_variable_get(:@namespace)).to eq('railscron')
      expect(engine.instance_variable_get(:@ttl)).to eq(described_class::DEFAULT_TTL)
    end
  end

  describe '#log_dispatch' do
    it 'stores dispatch record in Redis with TTL' do
      fire_time = Time.current

      allow(redis_client).to receive(:setex) do |key, ttl, value|
        expect(key).to match(/test:cron_dispatch:daily_report:\d+/)
        expect(ttl).to eq(3600)

        data = JSON.parse(value, symbolize_names: true)
        expect(data[:key]).to eq('daily_report')
        expect(data[:fire_time]).to eq(fire_time.to_i)
        expect(data[:node_id]).to eq('node-1')
        expect(data[:status]).to eq('dispatched')
        expect(data[:dispatched_at]).to be_within(1).of(Time.current.to_i)
      end

      result = engine.log_dispatch('daily_report', fire_time, 'node-1')

      expect(result).to be_a(Hash)
      expect(result[:key]).to eq('daily_report')
      expect(result[:fire_time]).to eq(fire_time.to_i)
      expect(result[:node_id]).to eq('node-1')
      expect(result[:status]).to eq('dispatched')
    end

    it 'allows custom status' do
      fire_time = Time.current

      allow(redis_client).to receive(:setex) do |_key, _ttl, value|
        data = JSON.parse(value, symbolize_names: true)
        expect(data[:status]).to eq('failed')
      end

      result = engine.log_dispatch('daily_report', fire_time, 'node-1', 'failed')

      expect(result[:status]).to eq('failed')
    end
  end

  describe '#find_dispatch' do
    it 'returns dispatch record when it exists in Redis' do
      fire_time = Time.current
      stored_data = {
        key: 'daily_report',
        fire_time: fire_time.to_i,
        dispatched_at: Time.current.to_i,
        node_id: 'node-1',
        status: 'dispatched'
      }

      allow(redis_client).to receive(:get).and_return(JSON.generate(stored_data))

      result = engine.find_dispatch('daily_report', fire_time)

      expect(result).to be_a(Hash)
      expect(result[:key]).to eq('daily_report')
      expect(result[:fire_time]).to be_a(Time)
      expect(result[:fire_time].to_i).to eq(fire_time.to_i)
      expect(result[:node_id]).to eq('node-1')
      expect(result[:status]).to eq('dispatched')
    end

    it 'returns nil when dispatch does not exist' do
      allow(redis_client).to receive(:get).and_return(nil)

      result = engine.find_dispatch('nonexistent', Time.current)

      expect(result).to be_nil
    end

    it 'converts Unix timestamps back to Time objects' do
      fire_time = Time.current
      dispatched_at = Time.current - 60
      stored_data = {
        key: 'test_key',
        fire_time: fire_time.to_i,
        dispatched_at: dispatched_at.to_i,
        node_id: 'node-1',
        status: 'dispatched'
      }

      allow(redis_client).to receive(:get).and_return(JSON.generate(stored_data))

      result = engine.find_dispatch('test_key', fire_time)

      expect(result[:fire_time]).to be_a(Time)
      expect(result[:dispatched_at]).to be_a(Time)
      expect(result[:fire_time].to_i).to eq(fire_time.to_i)
      expect(result[:dispatched_at].to_i).to eq(dispatched_at.to_i)
    end
  end

  describe '#dispatched?' do
    it 'returns true when dispatch exists' do
      fire_time = Time.current
      stored_data = {
        key: 'test',
        fire_time: fire_time.to_i,
        dispatched_at: Time.current.to_i,
        node_id: 'node-1',
        status: 'dispatched'
      }

      allow(redis_client).to receive(:get).and_return(JSON.generate(stored_data))

      expect(engine.dispatched?('test', fire_time)).to be true
    end

    it 'returns false when dispatch does not exist' do
      allow(redis_client).to receive(:get).and_return(nil)

      expect(engine.dispatched?('nonexistent', Time.current)).to be false
    end
  end

  describe 'Redis key format' do
    it 'uses correct key format' do
      fire_time = Time.current
      expected_key = "test:cron_dispatch:my_job:#{fire_time.to_i}"

      allow(redis_client).to receive(:setex) do |key, _ttl, _value|
        expect(key).to eq(expected_key)
      end

      engine.log_dispatch('my_job', fire_time, 'node-1')
    end
  end
end
