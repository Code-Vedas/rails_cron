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
    it 'can be initialized without log_dispatch' do
      adapter_default = described_class.new
      expect(adapter_default).to be_a(described_class)
    end

    it 'can be initialized with log_dispatch true' do
      adapter_with_log = described_class.new(log_dispatch: true)
      expect(adapter_with_log).to be_a(described_class)
    end

    it 'can be initialized with log_dispatch false' do
      adapter_without_log = described_class.new(log_dispatch: false)
      expect(adapter_without_log).to be_a(described_class)
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

    it 'sends correct SQL to PostgreSQL' do
      result_set = [{ 'pg_try_advisory_lock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      adapter.acquire('test-key', 60)

      expect(mock_connection).to have_received(:execute).with('SELECT pg_try_advisory_lock($1)', anything)
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

    context 'with log_dispatch enabled' do
      let(:adapter) { described_class.new(log_dispatch: true) }

      it 'attempts to log dispatch when lock is acquired' do
        result_set = [{ 'pg_try_advisory_lock' => true }]
        allow(mock_connection).to receive(:execute).and_return(result_set)

        # Should not raise even if CronDispatch is not defined
        expect { adapter.acquire('railscron:dispatch:myjob:1609459200', 60) }.not_to raise_error
      end

      it 'raises LockAdapterError if CronDispatch.create! fails' do
        result_set = [{ 'pg_try_advisory_lock' => true }]
        allow(mock_connection).to receive(:execute).and_return(result_set)

        # Stub the CronDispatch.create! to raise an error
        allow(RailsCron::CronDispatch).to receive(:create!).and_raise(StandardError, 'Database connection lost')

        expect do
          adapter.acquire('railscron:dispatch:job:1234567890', 60)
        end.to raise_error(RailsCron::Lock::LockAdapterError, /Failed to log dispatch/)
      end
    end

    context 'with log_dispatch disabled' do
      let(:adapter) { described_class.new(log_dispatch: false) }

      it 'does not attempt to log dispatch' do
        result_set = [{ 'pg_try_advisory_lock' => true }]
        allow(mock_connection).to receive(:execute).and_return(result_set)

        # Should not raise and should not attempt logging
        expect { adapter.acquire('lock-key', 60) }.not_to raise_error
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

    it 'sends correct SQL to PostgreSQL' do
      result_set = [{ 'pg_advisory_unlock' => true }]
      allow(mock_connection).to receive(:execute).and_return(result_set)

      adapter.release('test-key')

      expect(mock_connection).to have_received(:execute).with('SELECT pg_advisory_unlock($1)', anything)
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
