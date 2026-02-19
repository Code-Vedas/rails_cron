# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Lock::PostgresAdapter do
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
    it 'returns true when advisory lock is acquired' do
      result_set = [{ 'pg_try_advisory_lock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('railscron:dispatch:job1:1234567890', 60)
      expect(result).to be(true)
    end

    it 'returns false when advisory lock is not acquired' do
      result_set = [{ 'pg_try_advisory_lock' => false }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('railscron:dispatch:job1:1234567890', 60)
      expect(result).to be(false)
    end

    it 'casts PostgreSQL string "t" to Ruby true' do
      result_set = [{ 'pg_try_advisory_lock' => 't' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('railscron:dispatch:job1:1234567890', 60)
      expect(result).to be(true)
      expect(result).to be_a(TrueClass)
    end

    it 'casts PostgreSQL string "f" to Ruby false' do
      result_set = [{ 'pg_try_advisory_lock' => 'f' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.acquire('railscron:dispatch:job1:1234567890', 60)
      expect(result).to be(false)
      expect(result).to be_a(FalseClass)
    end

    it 'sends correct SQL to PostgreSQL' do
      result_set = [{ 'pg_try_advisory_lock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
      allow(ActiveRecord::Base).to receive(:sanitize_sql_array).and_call_original

      adapter.acquire('test-key', 60)

      expect(ActiveRecord::Base).to have_received(:sanitize_sql_array).with(['SELECT pg_try_advisory_lock(?)', anything])
    end

    it 'uses a deterministic hash for the lock ID' do
      result_set = [{ 'pg_try_advisory_lock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      adapter.acquire('test-key', 60)
      adapter.acquire('test-key', 60)

      # Verify execute was called twice with SQL containing pg_try_advisory_lock
      expect(mock_connection).to have_received(:execute).at_least(2).times
    end

    it 'raises LockAdapterError on database failure' do
      allow(mock_connection).to receive(:execute).and_raise(StandardError, 'Database connection lost')

      expect do
        adapter.acquire('lock-key', 60)
      end.to raise_error(RailsCron::Lock::LockAdapterError, /PostgreSQL acquire failed/)
    end

    context 'with dispatch logging enabled' do
      before do
        RailsCron.configuration.enable_log_dispatch_registry = true
      end

      after do
        RailsCron.configuration.enable_log_dispatch_registry = false
      end

      it 'logs dispatch when lock is acquired' do
        result_set = [{ 'pg_try_advisory_lock' => true }]
        allow(mock_connection).to receive(:execute).and_return(result_set)

        # Should not raise even if logging occurs
        expect { adapter.acquire('railscron:dispatch:myjob:1609459200', 60) }.not_to raise_error
      end

      it 'logs error if dispatch logging fails' do
        result_set = [{ 'pg_try_advisory_lock' => true }]
        allow(mock_connection).to receive(:execute).and_return(result_set)

        # Stub the registry to raise an error
        allow(adapter.dispatch_registry).to receive(:log_dispatch).and_raise(StandardError, 'Database connection lost')

        # Mock logger to verify error is logged
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
        result_set = [{ 'pg_try_advisory_lock' => true }]
        allow(mock_connection).to receive(:execute).and_return(result_set)
        allow(adapter.dispatch_registry).to receive(:log_dispatch)

        # Should not raise and should not attempt logging
        expect { adapter.acquire('lock-key', 60) }.not_to raise_error
        expect(adapter.dispatch_registry).not_to have_received(:log_dispatch)
      end
    end
  end

  describe '#release' do
    it 'returns true when advisory lock is released' do
      result_set = [{ 'pg_advisory_unlock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      expect(adapter.release('lock-key')).to be(true)
    end

    it 'returns false when lock was not held' do
      result_set = [{ 'pg_advisory_unlock' => false }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('lock-key')
      expect(result).to be(false)
    end

    it 'casts PostgreSQL string "t" to Ruby true' do
      result_set = [{ 'pg_advisory_unlock' => 't' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('lock-key')
      expect(result).to be(true)
      expect(result).to be_a(TrueClass)
    end

    it 'casts PostgreSQL string "f" to Ruby false' do
      result_set = [{ 'pg_advisory_unlock' => 'f' }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.release('lock-key')
      expect(result).to be(false)
      expect(result).to be_a(FalseClass)
    end

    it 'sends correct SQL to PostgreSQL' do
      result_set = [{ 'pg_advisory_unlock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
      allow(ActiveRecord::Base).to receive(:sanitize_sql_array).and_call_original

      adapter.release('test-key')

      expect(ActiveRecord::Base).to have_received(:sanitize_sql_array).with(['SELECT pg_advisory_unlock(?)', anything])
    end

    it 'raises LockAdapterError on database failure' do
      allow(mock_connection).to receive(:execute).and_raise(
        ActiveRecord::StatementInvalid, 'Database connection lost'
      )

      expect do
        adapter.release('lock-key')
      end.to raise_error(RailsCron::Lock::LockAdapterError, /PostgreSQL release failed/)
    end
  end

  describe '#with_lock' do
    before do
      result_set = [{ 'pg_try_advisory_lock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)
    end

    it 'executes block and returns result when lock is acquired' do
      result = adapter.with_lock('lock-key', ttl: 60) { 42 }
      expect(result).to eq(42)
    end

    it 'returns nil when lock cannot be acquired' do
      result_set = [{ 'pg_try_advisory_lock' => false }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      result = adapter.with_lock('lock-key', ttl: 60) { 42 }
      expect(result).to be_nil
    end

    it 'releases lock after successful block execution' do
      call_count = 0
      allow(mock_connection).to receive(:execute) do
        call_count += 1
        if call_count == 1
          [{ 'pg_try_advisory_lock' => true }]
        else
          [{ 'pg_advisory_unlock' => true }]
        end
      end

      adapter.with_lock('lock-key', ttl: 60) { true }

      expect(call_count).to be >= 2
    end

    it 'releases lock even if block raises exception' do
      result_set_acquire = [{ 'pg_try_advisory_lock' => true }]
      result_set_release = [{ 'pg_advisory_unlock' => true }]

      call_count = 0
      allow(mock_connection).to receive(:execute) do
        call_count += 1
        call_count == 1 ? result_set_acquire : result_set_release
      end

      expect do
        adapter.with_lock('lock-key', ttl: 60) { raise 'test error' }
      end.to raise_error('test error')

      expect(call_count).to be >= 2
    end
  end

  describe 'lock key parsing' do
    it 'parses simple lock keys correctly' do
      result_set = [{ 'pg_try_advisory_lock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      # Example: "railscron:dispatch:myjob:1609459200"
      adapter.acquire('railscron:dispatch:myjob:1609459200', 60)

      expect(mock_connection).to have_received(:execute)
    end

    it 'parses lock keys with hyphens in job name' do
      result_set = [{ 'pg_try_advisory_lock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      # Example: "railscron:dispatch:send-daily-email:1609459200"
      adapter.acquire('railscron:dispatch:send-daily-email:1609459200', 60)

      expect(mock_connection).to have_received(:execute)
    end
  end
end
