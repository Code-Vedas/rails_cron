# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'fakeredis'

RSpec.describe RailsCron::Lock::RedisAdapter do
  let(:redis_client) { Redis.new }
  let(:adapter) { described_class.new(redis_client) }

  before do
    allow(Redis).to receive(:new).and_return(redis_client)
  end

  describe '#initialize' do
    it 'requires a redis client' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /redis client is required/)
    end

    it 'requires a client with set method' do
      invalid_client = Object.new
      expect { described_class.new(invalid_client) }.to raise_error(ArgumentError, /redis client must respond to :set and :eval/)
    end

    it 'accepts a valid redis client' do
      expect(adapter).to be_a(described_class)
    end

    it 'has a dispatch_registry method' do
      expect(adapter).to respond_to(:dispatch_registry)
    end

    it 'returns a RedisEngine for dispatch_registry' do
      expect(adapter.dispatch_registry).to be_a(RailsCron::Dispatch::RedisEngine)
    end
  end

  describe '#acquire' do
    it 'returns true when lock is acquired' do
      allow(redis_client).to receive(:set).and_return('OK')

      result = adapter.acquire('lock-key', 60)
      expect(result).to be(true)
    end

    it 'passes correct parameters to Redis SET' do
      allow(redis_client).to receive(:set).and_return('OK')

      adapter.acquire('my-key', 120)

      expect(redis_client).to have_received(:set).with(
        'my-key',
        anything,
        nx: true,
        px: 120_000
      )
    end

    it 'returns false when lock is already held' do
      allow(redis_client).to receive(:set).and_return(nil)

      result = adapter.acquire('lock-key', 60)
      expect(result).to be(false)
    end

    it 'stores lock value for release' do
      allow(redis_client).to receive(:set).and_return('OK')
      allow(redis_client).to receive(:eval)

      adapter.acquire('key1', 60)
      adapter.release('key1')

      expect(redis_client).to have_received(:eval)
    end

    it 'raises LockAdapterError on Redis failure' do
      allow(redis_client).to receive(:set).and_raise(StandardError, 'Connection failed')

      expect { adapter.acquire('key', 60) }.to raise_error(
        RailsCron::Lock::LockAdapterError,
        /Redis acquire failed/
      )
    end

    it 'generates different lock values for each acquisition' do
      first_value = nil
      second_value = nil

      allow(redis_client).to receive(:set) do |_key, value, **_opts|
        first_value = value if first_value.nil?
        second_value = value
        'OK'
      end

      adapter.acquire('key1', 60)
      new_adapter = described_class.new(redis_client)
      new_adapter.acquire('key2', 60)

      expect(first_value).to be_a(String)
      expect(second_value).to be_a(String)
      # Different UUIDs
      expect(first_value).not_to eq(second_value)
    end

    context 'with dispatch logging enabled' do
      before do
        RailsCron.configuration.enable_log_dispatch_registry = true
      end

      after do
        RailsCron.configuration.enable_log_dispatch_registry = false
      end

      it 'logs dispatch when lock is acquired' do
        allow(redis_client).to receive(:set).and_return('OK')

        expect { adapter.acquire('railscron:dispatch:myjob:1609459200', 60) }.not_to raise_error
      end

      it 'logs error if dispatch logging fails' do
        allow(redis_client).to receive(:set).and_return('OK')
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
        allow(redis_client).to receive(:set).and_return('OK')
        allow(adapter.dispatch_registry).to receive(:log_dispatch)

        expect { adapter.acquire('lock-key', 60) }.not_to raise_error
        expect(adapter.dispatch_registry).not_to have_received(:log_dispatch)
      end
    end
  end

  describe '#release' do
    it 'returns true when lock is released' do
      allow(redis_client).to receive_messages(set: 'OK', eval: 1)

      adapter.acquire('lock-key', 60)
      result = adapter.release('lock-key')

      expect(result).to be(true)
    end

    it 'returns false when lock was not held' do
      result = adapter.release('non-existent')
      expect(result).to be(false)
    end

    it 'returns false when lock is held by another process' do
      allow(redis_client).to receive_messages(set: 'OK', eval: 0)

      adapter.acquire('lock-key', 60)
      result = adapter.release('lock-key')

      expect(result).to be(false)
    end

    it 'uses Lua script to safely release' do
      allow(redis_client).to receive_messages(set: 'OK', eval: 1)

      adapter.acquire('my-key', 60)
      adapter.release('my-key')

      expect(redis_client).to have_received(:eval) do |script, **kwargs|
        expect(script).to include('redis.call')
        expect(kwargs[:keys]).to eq(['my-key'])
        expect(kwargs[:argv]).to be_an(Array)
      end
    end

    it 'raises LockAdapterError on Redis failure' do
      allow(redis_client).to receive(:set).and_return('OK')
      allow(redis_client).to receive(:eval).and_raise(StandardError, 'Connection failed')

      adapter.acquire('lock-key', 60)

      expect { adapter.release('lock-key') }.to raise_error(
        RailsCron::Lock::LockAdapterError,
        /Redis release failed/
      )
    end
  end

  describe '#with_lock' do
    before do
      allow(redis_client).to receive_messages(set: 'OK', eval: 1)
    end

    it 'executes block and returns result when lock is acquired' do
      result = adapter.with_lock('key', ttl: 60) { 42 }
      expect(result).to eq(42)
    end

    it 'returns nil when lock cannot be acquired' do
      allow(redis_client).to receive(:set).and_return(nil)

      result = adapter.with_lock('key', ttl: 60) { 42 }
      expect(result).to be_nil
    end

    it 'releases lock after block execution' do
      adapter.with_lock('key', ttl: 60) { true }

      expect(redis_client).to have_received(:eval)
    end

    it 'releases lock even if block raises exception' do
      allow(redis_client).to receive(:eval).and_return(1)

      expect do
        adapter.with_lock('key', ttl: 60) { raise 'test error' }
      end.to raise_error('test error')

      expect(redis_client).to have_received(:eval)
    end
  end
end
