# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Lock::MySQLAdapter do
  let(:mock_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:adapter) { described_class.new }

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
  end

  describe '#initialize' do
    it 'can be initialized' do
      adapter = described_class.new
      expect(adapter).to be_a(described_class)
    end

    it 'has a dispatch_registry method' do
      expect(adapter).to respond_to(:dispatch_registry)
    end

    it 'returns a DatabaseEngine for dispatch_registry' do
      expect(adapter.dispatch_registry).to be_a(RailsCron::Dispatch::DatabaseEngine)
    end
  end

  describe '#acquire' do
    it 'returns true when lock is acquired' do
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('railscron:dispatch:job1:1234567890', 60)
      expect(result).to be(true)
      expect(result).to be_a(TrueClass)
    end

    it 'returns false when lock is not acquired' do
      result_set = [{ 'lock_result' => 0 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('railscron:dispatch:job1:1234567890', 60)
      expect(result).to be(false)
      expect(result).to be_a(FalseClass)
    end

    it 'handles nil result from GET_LOCK (error case) as false' do
      result_set = [{ 'lock_result' => nil }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('railscron:dispatch:job1:1234567890', 60)
      expect(result).to be(false)
    end

    it 'sends correct SQL with GET_LOCK with stable alias' do
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
      allow(ActiveRecord::Base).to receive(:sanitize_sql_array).and_call_original

      adapter.acquire('test-key', 60)

      expect(ActiveRecord::Base).to have_received(:sanitize_sql_array).with(
        ['SELECT GET_LOCK(?, 0) as lock_result', 'test-key']
      )
    end

    it 'shortens lock names longer than 64 characters using hash-based approach' do
      long_key = 'a' * 100
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
      logger_double = instance_double(Logger)
      allow(RailsCron).to receive(:logger).and_return(logger_double)
      allow(logger_double).to receive(:warn)

      adapter.acquire(long_key, 60)

      expect(logger_double).to have_received(:warn) do |message|
        expect(message).to include('hash-based shortening')
        expect(message).to include('avoid collisions')
      end
    end

    it 'raises LockAdapterError on database failure' do
      allow(mock_connection).to receive(:execute).and_raise(StandardError, 'Connection lost')

      expect do
        adapter.acquire('lock-key', 60)
      end.to raise_error(RailsCron::Lock::LockAdapterError, /MySQL acquire failed/)
    end

    context 'with dispatch logging enabled' do
      before do
        RailsCron.configuration.enable_log_dispatch_registry = true
      end

      after do
        RailsCron.configuration.enable_log_dispatch_registry = false
      end

      it 'logs dispatch when lock is acquired' do
        result_set = [{ 'lock_result' => 1 }]
        allow(mock_connection).to receive(:execute).and_return(result_set)
        allow(adapter).to receive(:log_dispatch_attempt).and_call_original
        allow(adapter.dispatch_registry).to receive(:log_dispatch)

        adapter.acquire('railscron:dispatch:myjob:1609459200', 60)

        expect(adapter).to have_received(:log_dispatch_attempt).with('railscron:dispatch:myjob:1609459200')
      end

      it 'does not log dispatch when lock is not acquired' do
        result_set = [{ 'lock_result' => 0 }]
        allow(mock_connection).to receive(:execute).and_return(result_set)
        allow(adapter).to receive(:log_dispatch_attempt)

        adapter.acquire('railscron:dispatch:myjob:1609459200', 60)

        expect(adapter).not_to have_received(:log_dispatch_attempt)
      end

      it 'logs error if dispatch logging fails' do
        result_set = [{ 'lock_result' => 1 }]
        allow(mock_connection).to receive(:execute).and_return(result_set)
        allow(adapter.dispatch_registry).to receive(:log_dispatch).and_raise(StandardError, 'DB error')

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
        result_set = [{ 'lock_result' => 1 }]
        allow(mock_connection).to receive(:execute).and_return(result_set)
        allow(adapter.dispatch_registry).to receive(:log_dispatch)

        expect { adapter.acquire('lock-key', 60) }.not_to raise_error
        expect(adapter.dispatch_registry).not_to have_received(:log_dispatch)
      end
    end
  end

  describe '#release' do
    it 'returns true when lock is released' do
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('lock-key')
      expect(result).to be(true)
      expect(result).to be_a(TrueClass)
    end

    it 'returns false when lock was not held' do
      result_set = [{ 'lock_result' => 0 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('lock-key')
      expect(result).to be(false)
      expect(result).to be_a(FalseClass)
    end

    it 'handles nil result from RELEASE_LOCK (error case) as false' do
      result_set = [{ 'lock_result' => nil }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('lock-key')
      expect(result).to be(false)
    end

    it 'sends correct SQL with stable alias' do
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
      allow(ActiveRecord::Base).to receive(:sanitize_sql_array).and_call_original

      adapter.release('test-key')

      expect(ActiveRecord::Base).to have_received(:sanitize_sql_array).with(
        ['SELECT RELEASE_LOCK(?) as lock_result', 'test-key']
      )
    end

    it 'shortens lock names longer than 64 characters using hash-based approach' do
      long_key = 'b' * 100
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
      logger_double = instance_double(Logger)
      allow(RailsCron).to receive(:logger).and_return(logger_double)
      allow(logger_double).to receive(:warn)

      adapter.release(long_key)

      expect(logger_double).to have_received(:warn) do |message|
        expect(message).to include('hash-based shortening')
        expect(message).to include('avoid collisions')
      end
    end

    it 'raises LockAdapterError on database failure' do
      allow(mock_connection).to receive(:execute).and_raise(
        ActiveRecord::StatementInvalid, 'Connection lost'
      )

      expect do
        adapter.release('lock-key')
      end.to raise_error(RailsCron::Lock::LockAdapterError, /MySQL release failed/)
    end
  end

  describe '#with_lock' do
    before do
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
    end

    it 'executes block and returns result when lock is acquired' do
      result = adapter.with_lock('lock-key', ttl: 60) { 42 }
      expect(result).to eq(42)
    end

    it 'returns nil when lock cannot be acquired' do
      result_set = [{ 'lock_result' => 0 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.with_lock('lock-key', ttl: 60) { 42 }
      expect(result).to be_nil
    end

    it 'releases lock after successful block execution' do
      result_set = [{ 'lock_result' => 1 }]
      call_count = 0
      allow(mock_connection).to receive(:execute) do
        call_count += 1
        result_set
      end

      adapter.with_lock('lock-key', ttl: 60) { true }

      expect(call_count).to be >= 2
    end

    it 'releases lock even if block raises exception' do
      result_set = [{ 'lock_result' => 1 }]

      call_count = 0
      allow(mock_connection).to receive(:execute) do
        call_count += 1
        result_set
      end

      expect do
        adapter.with_lock('lock-key', ttl: 60) { raise 'test error' }
      end.to raise_error('test error')

      expect(call_count).to be >= 2
    end
  end

  describe 'lock key parsing' do
    it 'parses simple lock keys correctly' do
      result_set = [{ 'lock_acquired' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      # Should not raise
      expect { adapter.acquire('railscron:dispatch:simple-job:1609459200', 60) }.not_to raise_error
    end

    it 'parses lock keys with colons in the job name' do
      result_set = [{ 'lock_acquired' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      # Job name contains colons (e.g., "job:subname:action")
      expect { adapter.acquire('railscron:dispatch:job:subname:action:1609459200', 60) }.not_to raise_error
    end
  end

  describe 'lock name length limit' do
    it 'allows lock names up to 64 characters' do
      key = 'a' * 64
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      expect do
        adapter.acquire(key, 60)
      end.not_to raise_error
    end

    it 'uses hash-based shortening for lock names exceeding 64 characters' do
      key = 'a' * 65
      result_set = [{ 'lock_result' => 1 }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
      logger_double = instance_double(Logger)
      allow(RailsCron).to receive(:logger).and_return(logger_double)
      allow(logger_double).to receive(:warn)

      adapter.acquire(key, 60)

      expect(logger_double).to have_received(:warn) do |message|
        expect(message).to include('exceeds MySQL named lock limit')
        expect(message).to include('hash-based shortening')
      end
    end

    it 'normalizes long keys to exactly 64 characters' do
      long_key = 'very_long_key_' * 10 # ~140 chars
      normalized = adapter.send(:normalize_lock_name, long_key)
      expect(normalized.length).to eq(64)
    end

    it 'produces different normalized keys for distinct long keys' do
      key1 = 'a' * 100
      key2 = "#{'a' * 99}b"
      normalized1 = adapter.send(:normalize_lock_name, key1)
      normalized2 = adapter.send(:normalize_lock_name, key2)
      expect(normalized1).not_to eq(normalized2)
    end

    context 'when RailsCron.logger is nil' do
      it 'handles long keys in acquire without error when logger is nil' do
        long_key = 'x' * 100
        result_set = [{ 'lock_result' => 1 }]
        allow(mock_connection).to receive(:execute).and_return(result_set)
        allow(RailsCron).to receive(:logger).and_return(nil)

        expect do
          adapter.acquire(long_key, 60)
        end.not_to raise_error
      end

      it 'handles long keys in release without error when logger is nil' do
        long_key = 'y' * 100
        result_set = [{ 'lock_result' => 1 }]
        allow(mock_connection).to receive(:execute).and_return(result_set)
        allow(RailsCron).to receive(:logger).and_return(nil)

        expect do
          adapter.release(long_key)
        end.not_to raise_error
      end

      it 'normalizes long keys correctly even when logger is nil' do
        long_key = 'z' * 100
        allow(RailsCron).to receive(:logger).and_return(nil)

        normalized = adapter.send(:normalize_lock_name, long_key)
        expect(normalized.length).to eq(64)
      end
    end
  end

  describe 'cast_to_boolean coverage' do
    it 'handles true boolean value directly' do
      result_set = [{ 'lock_result' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(true)
    end

    it 'handles false boolean value directly' do
      result_set = [{ 'lock_result' => false }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(false)
    end

    it 'handles string "t" via regex fallback' do
      result_set = [{ 'lock_result' => 't' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(true)
    end

    it 'handles string "f" via regex fallback' do
      result_set = [{ 'lock_result' => 'f' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(false)
    end

    it 'handles string "false" via regex fallback' do
      result_set = [{ 'lock_result' => 'false' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(false)
    end

    it 'handles string "0" via regex fallback' do
      result_set = [{ 'lock_result' => '0' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(false)
    end

    it 'handles string "1" via regex fallback as truthy' do
      result_set = [{ 'lock_result' => '1' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(true)
    end

    it 'handles empty string via regex fallback as false' do
      result_set = [{ 'lock_result' => '' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(false)
    end

    it 'handles arbitrary string via regex fallback as true' do
      result_set = [{ 'lock_result' => 'yes' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(true)
    end
  end

  describe 'result row format handling' do
    it 'handles array result row format in acquire (non-hash format)' do
      # Some MySQL adapters may return arrays instead of hashes
      result_set = [[1]]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(true)
    end

    it 'handles array result row format in release (non-hash format)' do
      # Some MySQL adapters may return arrays instead of hashes
      result_set = [[1]]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('test-key')
      expect(result).to be(true)
    end

    it 'handles nil result row in acquire with safe navigation' do
      # Empty result set
      result_set = []
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('test-key', 60)
      expect(result).to be(false)
    end

    it 'handles nil result row in release with safe navigation' do
      # Empty result set
      result_set = []
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('test-key')
      expect(result).to be(false)
    end
  end
end
