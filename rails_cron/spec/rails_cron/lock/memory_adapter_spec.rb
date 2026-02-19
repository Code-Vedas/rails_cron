# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Lock::MemoryAdapter do
  let(:adapter) { described_class.new }

  describe 'initialization' do
    it 'creates a new memory adapter' do
      adapter = described_class.new
      expect(adapter).to be_a(described_class)
    end

    it 'has a dispatch_registry method' do
      expect(adapter).to respond_to(:dispatch_registry)
    end

    it 'returns a MemoryEngine for dispatch_registry' do
      expect(adapter.dispatch_registry).to be_a(RailsCron::Dispatch::MemoryEngine)
    end
  end

  describe '#acquire' do
    it 'acquires a lock for a new key' do
      expect(adapter.acquire('key1', 60)).to be(true)
    end

    it 'returns false if lock is already held' do
      adapter.acquire('key1', 60)
      expect(adapter.acquire('key1', 60)).to be(false)
    end

    it 'allows reacquiring after TTL expiration' do
      adapter.acquire('key1', 1) # 1 second TTL
      expect(adapter.acquire('key1', 60)).to be(false)
      sleep(1.1)
      expect(adapter.acquire('key1', 60)).to be(true)
    end

    it 'allows different locks for different keys' do
      expect(adapter.acquire('key1', 60)).to be(true)
      expect(adapter.acquire('key2', 60)).to be(true)
      expect(adapter.acquire('key3', 60)).to be(true)
    end

    it 'tracks TTL correctly with large values' do
      adapter.acquire('key1', 3600)
      expect(adapter.acquire('key1', 60)).to be(false)
    end

    context 'with dispatch logging enabled' do
      before do
        RailsCron.configuration.enable_log_dispatch_registry = true
      end

      after do
        RailsCron.configuration.enable_log_dispatch_registry = false
      end

      it 'logs dispatch when lock is acquired' do
        expect { adapter.acquire('railscron:dispatch:myjob:1609459200', 60) }.not_to raise_error
      end

      it 'logs error if dispatch logging fails' do
        allow(adapter.dispatch_registry).to receive(:log_dispatch).and_raise(StandardError, 'Registry error')

        logger = instance_double(Logger)
        allow(RailsCron.configuration).to receive(:logger).and_return(logger)
        allow(logger).to receive(:error)

        expect { adapter.acquire('railscron:dispatch:job:1234567890', 60) }.not_to raise_error
        expect(logger).to have_received(:error).with(/Failed to log dispatch/)
      end
    end

    context 'with dispatch logging disabled' do
      before do
        RailsCron.configuration.enable_log_dispatch_registry = false
      end

      it 'does not attempt to log dispatch' do
        allow(adapter.dispatch_registry).to receive(:log_dispatch)

        expect { adapter.acquire('lock-key', 60) }.not_to raise_error
        expect(adapter.dispatch_registry).not_to have_received(:log_dispatch)
      end
    end
  end

  describe '#release' do
    it 'releases a held lock' do
      adapter.acquire('key1', 60)
      expect(adapter.release('key1')).to be(true)
    end

    it 'allows reacquiring after release' do
      adapter.acquire('key1', 60)
      adapter.release('key1')
      expect(adapter.acquire('key1', 60)).to be(true)
    end

    it 'returns false when releasing a non-held lock' do
      expect(adapter.release('non-existent')).to be(false)
    end

    it 'returns false when releasing the same lock twice' do
      adapter.acquire('key1', 60)
      expect(adapter.release('key1')).to be(true)
      expect(adapter.release('key1')).to be(false)
    end
  end

  describe '#with_lock' do
    it 'executes block and returns result when lock is acquired' do
      result = adapter.with_lock('key1', ttl: 60) { 42 }
      expect(result).to eq(42)
    end

    it 'returns nil when lock cannot be acquired' do
      adapter.acquire('key1', 60)
      result = adapter.with_lock('key1', ttl: 60) { 42 }
      expect(result).to be_nil
    end

    it 'releases lock after block execution' do
      adapter.with_lock('key1', ttl: 60) { true }
      expect(adapter.acquire('key1', 60)).to be(true)
    end

    it 'releases lock even if block raises exception' do
      expect do
        adapter.with_lock('key1', ttl: 60) { raise 'test error' }
      end.to raise_error('test error')

      expect(adapter.acquire('key1', 60)).to be(true)
    end

    it 'returns block result with complex objects' do
      data = { key: 'value', array: [1, 2, 3] }
      result = adapter.with_lock('key1', ttl: 60) { data }
      expect(result).to eq(data)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent acquire calls safely' do
      results = []
      threads = Array.new(10) do
        Thread.new do
          results << adapter.acquire('shared-key', 60)
        end
      end
      threads.each(&:join)

      # Only one thread should successfully acquire
      expect(results.count(true)).to eq(1)
      expect(results.count(false)).to eq(9)
    end
  end

  describe 'isolation' do
    it 'does not interfere between multiple adapter instances' do
      adapter1 = described_class.new
      adapter2 = described_class.new

      expect(adapter1.acquire('key1', 60)).to be(true)
      # adapter2 has its own lock storage
      expect(adapter2.acquire('key1', 60)).to be(true)
    end
  end
end
