# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Dispatch::MemoryEngine do
  subject(:engine) { described_class.new }

  describe '#log_dispatch' do
    it 'stores dispatch record in memory' do
      fire_time = Time.current
      result = engine.log_dispatch('daily_report', fire_time, 'node-1')

      expect(result).to be_a(Hash)
      expect(result[:key]).to eq('daily_report')
      expect(result[:fire_time]).to eq(fire_time)
      expect(result[:node_id]).to eq('node-1')
      expect(result[:status]).to eq('dispatched')
      expect(result[:dispatched_at]).to be_within(1.second).of(Time.current)
    end

    it 'allows custom status' do
      fire_time = Time.current
      result = engine.log_dispatch('daily_report', fire_time, 'node-1', 'failed')

      expect(result[:status]).to eq('failed')
    end

    it 'overwrites existing dispatch with same key and fire_time' do
      fire_time = Time.current
      engine.log_dispatch('daily_report', fire_time, 'node-1', 'dispatched')
      result = engine.log_dispatch('daily_report', fire_time, 'node-2', 'failed')

      expect(result[:node_id]).to eq('node-2')
      expect(result[:status]).to eq('failed')
    end

    it 'is thread-safe' do
      fire_time = Time.current
      threads = Array.new(10) do |i|
        Thread.new do
          engine.log_dispatch("key-#{i}", fire_time, "node-#{i}")
        end
      end

      threads.each(&:join)

      expect(engine.size).to eq(10)
    end
  end

  describe '#find_dispatch' do
    it 'returns dispatch record when it exists' do
      fire_time = Time.current
      engine.log_dispatch('daily_report', fire_time, 'node-1')

      result = engine.find_dispatch('daily_report', fire_time)

      expect(result).to be_a(Hash)
      expect(result[:key]).to eq('daily_report')
      expect(result[:fire_time]).to eq(fire_time)
      expect(result[:node_id]).to eq('node-1')
    end

    it 'returns nil when dispatch does not exist' do
      result = engine.find_dispatch('nonexistent', Time.current)

      expect(result).to be_nil
    end

    it 'distinguishes between different fire times for same key' do
      fire_time1 = Time.current
      fire_time2 = fire_time1 + 60

      engine.log_dispatch('daily_report', fire_time1, 'node-1')
      engine.log_dispatch('daily_report', fire_time2, 'node-2')

      result1 = engine.find_dispatch('daily_report', fire_time1)
      result2 = engine.find_dispatch('daily_report', fire_time2)

      expect(result1[:node_id]).to eq('node-1')
      expect(result2[:node_id]).to eq('node-2')
    end

    it 'is thread-safe' do
      fire_time = Time.current
      engine.log_dispatch('test_key', fire_time, 'node-1')

      threads = Array.new(100) do
        Thread.new do
          engine.find_dispatch('test_key', fire_time)
        end
      end

      results = threads.map(&:value)

      expect(results).to all(be_a(Hash))
      expect(results).to all(have_key(:key))
    end
  end

  describe '#dispatched?' do
    it 'returns true when dispatch exists' do
      fire_time = Time.current
      engine.log_dispatch('daily_report', fire_time, 'node-1')

      expect(engine.dispatched?('daily_report', fire_time)).to be true
    end

    it 'returns false when dispatch does not exist' do
      expect(engine.dispatched?('nonexistent', Time.current)).to be false
    end
  end

  describe '#clear' do
    it 'removes all stored dispatches' do
      engine.log_dispatch('key1', Time.current, 'node-1')
      engine.log_dispatch('key2', Time.current + 60, 'node-2')

      expect(engine.size).to eq(2)

      engine.clear

      expect(engine.size).to eq(0)
    end

    it 'is thread-safe' do
      10.times { |i| engine.log_dispatch("key-#{i}", Time.current, 'node-1') }

      threads = Array.new(5) do
        Thread.new { engine.clear }
      end

      threads.each(&:join)

      expect(engine.size).to eq(0)
    end
  end

  describe '#size' do
    it 'returns the number of stored dispatches' do
      expect(engine.size).to eq(0)

      engine.log_dispatch('key1', Time.current, 'node-1')
      expect(engine.size).to eq(1)

      engine.log_dispatch('key2', Time.current + 60, 'node-2')
      expect(engine.size).to eq(2)
    end

    it 'is thread-safe' do
      threads = Array.new(50) do |i|
        Thread.new do
          engine.log_dispatch("key-#{i}", Time.current, 'node-1')
        end
      end

      threads.each(&:join)

      expect(engine.size).to eq(50)
    end
  end
end
