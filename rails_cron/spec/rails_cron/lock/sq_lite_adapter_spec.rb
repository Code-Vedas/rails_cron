# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails_helper'

describe RailsCron::Lock::SQLiteAdapter do
  let(:adapter) { described_class.new }

  before do
    RailsCron::CronLock.delete_all
  end

  describe 'initialization' do
    it 'creates a new sqlite adapter' do
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
    it 'returns true when lock is acquired for new key' do
      result = adapter.acquire('test:key:123', 60)
      expect(result).to be(true)
    end

    it 'creates a lock record in database' do
      adapter.acquire('test:key:456', 60)

      lock = RailsCron::CronLock.find_by(key: 'test:key:456')
      expect(lock).to be_present
      expect(lock.expires_at).to be > Time.current
    end

    it 'returns false when lock is already held' do
      adapter.acquire('test:key:789', 60)

      result = adapter.acquire('test:key:789', 60)
      expect(result).to be(false)
    end

    it 'stores correct TTL expiration time' do
      now = Time.current
      adapter.acquire('test:key:ttl', 120)

      lock = RailsCron::CronLock.find_by(key: 'test:key:ttl')
      expect(lock.expires_at).to be_within(2.seconds).of(now + 120.seconds)
    end

    it 'raises LockAdapterError on database failure' do
      allow(RailsCron::CronLock).to receive(:create!).and_raise(StandardError, 'DB error')

      expect do
        adapter.acquire('test:key:error', 60)
      end.to raise_error(RailsCron::Lock::LockAdapterError, /SQLite acquire failed/)
    end

    it 'allows reacquiring after lock expires' do
      adapter.acquire('test:key:expire', 1) # 1 second TTL

      # Lock is held
      expect(adapter.acquire('test:key:expire', 1)).to be(false)

      # Wait for expiration
      sleep 1.1

      # Should be able to acquire again
      result = adapter.acquire('test:key:expire', 1)
      expect(result).to be(true)
    end

    it 'allows reacquiring of different keys' do
      adapter.acquire('key:a', 60)
      adapter.acquire('key:b', 60)

      # Both should be held
      expect(adapter.acquire('key:a', 60)).to be(false)
      expect(adapter.acquire('key:b', 60)).to be(false)
    end

    it 'allows different locks for different keys' do
      result_a = adapter.acquire('lock:job:a:1234', 60)
      result_b = adapter.acquire('lock:job:b:5678', 60)

      expect(result_a).to be(true)
      expect(result_b).to be(true)
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
        allow(adapter.dispatch_registry).to receive(:log_dispatch)

        expect { adapter.acquire('lock-key', 60) }.not_to raise_error
        expect(adapter.dispatch_registry).not_to have_received(:log_dispatch)
      end
    end
  end

  describe '#release' do
    it 'returns true when releasing a held lock' do
      adapter.acquire('test:release:123', 60)

      result = adapter.release('test:release:123')
      expect(result).to be(true)
    end

    it 'deletes lock record from database' do
      adapter.acquire('test:release:456', 60)
      adapter.release('test:release:456')

      lock = RailsCron::CronLock.find_by(key: 'test:release:456')
      expect(lock).to be_nil
    end

    it 'returns false when releasing non-held lock' do
      result = adapter.release('test:release:nonexistent')
      expect(result).to be(false)
    end

    it 'returns false when releasing the same lock twice' do
      adapter.acquire('test:release:789', 60)

      first_release = adapter.release('test:release:789')
      second_release = adapter.release('test:release:789')

      expect(first_release).to be(true)
      expect(second_release).to be(false)
    end

    it 'allows reacquiring after release' do
      key = 'test:reacquire'
      adapter.acquire(key, 60)
      adapter.release(key)

      result = adapter.acquire(key, 60)
      expect(result).to be(true)
    end

    it 'raises LockAdapterError on database failure' do
      adapter.acquire('test:key:error', 60)
      allow(RailsCron::CronLock).to receive(:where).and_raise(StandardError, 'DB error')

      expect do
        adapter.release('test:key:error')
      end.to raise_error(RailsCron::Lock::LockAdapterError, /SQLite release failed/)
    end
  end

  describe '#with_lock' do
    it 'executes block and returns result when lock is acquired' do
      result = adapter.with_lock('test:block:123', ttl: 60) do
        'success'
      end

      expect(result).to eq('success')
    end

    it 'releases lock after block execution' do
      adapter.with_lock('test:block:456', ttl: 60) do
        'done'
      end

      lock = RailsCron::CronLock.find_by(key: 'test:block:456')
      expect(lock).to be_nil
    end

    it 'releases lock even if block raises exception' do
      expect do
        adapter.with_lock('test:block:789', ttl: 60) do
          raise 'test error'
        end
      end.to raise_error('test error')

      lock = RailsCron::CronLock.find_by(key: 'test:block:789')
      expect(lock).to be_nil
    end

    it 'returns nil when lock cannot be acquired' do
      adapter.acquire('test:block:unavailable', 60)

      result = adapter.with_lock('test:block:unavailable', ttl: 60) do
        'should not execute'
      end

      expect(result).to be_nil
    end

    it 'executes block and returns complex result' do
      obj = { key: 'value', nested: { data: [1, 2, 3] } }

      result = adapter.with_lock('test:block:complex', ttl: 60) do
        obj
      end

      expect(result).to eq(obj)
    end

    it 'executes block and returns block result with complex objects' do
      result = adapter.with_lock('test:block:objects', ttl: 60) do
        { status: 'completed', items: %w[a b c] }
      end

      expect(result).to eq(status: 'completed', items: %w[a b c])
    end
  end

  describe 'Lock model' do
    it 'validates presence of key' do
      lock = RailsCron::CronLock.new(key: nil, acquired_at: Time.current, expires_at: Time.current + 60)
      expect(lock).not_to be_valid
      expect(lock.errors[:key]).to be_present
    end

    it 'enforces unique constraint on key' do
      RailsCron::CronLock.create!(key: 'unique:key', acquired_at: Time.current, expires_at: Time.current + 60)

      dup = RailsCron::CronLock.new(key: 'unique:key', acquired_at: Time.current, expires_at: Time.current + 60)
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'validates acquired_at presence' do
      lock = RailsCron::CronLock.new(key: 'test', acquired_at: nil, expires_at: Time.current + 60)
      expect(lock).not_to be_valid
      expect(lock.errors[:acquired_at]).to be_present
    end

    it 'validates expires_at presence' do
      lock = RailsCron::CronLock.new(key: 'test', acquired_at: Time.current, expires_at: nil)
      expect(lock).not_to be_valid
      expect(lock.errors[:expires_at]).to be_present
    end

    describe '.cleanup_expired' do
      it 'deletes expired locks' do
        now = Time.current
        past = now - 10.seconds

        RailsCron::CronLock.create!(key: 'expired:1', acquired_at: past, expires_at: past + 5.seconds)
        RailsCron::CronLock.create!(key: 'expired:2', acquired_at: past, expires_at: past + 5.seconds)

        deleted = RailsCron::CronLock.cleanup_expired
        expect(deleted).to eq(2)
      end

      it 'does not delete valid locks' do
        now = Time.current
        future = now + 100.seconds

        RailsCron::CronLock.create!(key: 'valid:1', acquired_at: now, expires_at: future)

        deleted = RailsCron::CronLock.cleanup_expired
        expect(deleted).to eq(0)

        lock = RailsCron::CronLock.find_by(key: 'valid:1')
        expect(lock).to be_present
      end

      it 'deletes only expired locks, keeps valid ones' do
        now = Time.current

        RailsCron::CronLock.create!(key: 'expired', acquired_at: now - 10, expires_at: now - 5)
        RailsCron::CronLock.create!(key: 'valid', acquired_at: now, expires_at: now + 100)

        deleted = RailsCron::CronLock.cleanup_expired
        expect(deleted).to eq(1)

        expect(RailsCron::CronLock.find_by(key: 'expired')).to be_nil
        expect(RailsCron::CronLock.find_by(key: 'valid')).to be_present
      end
    end

    describe '#not_expired?' do
      it 'returns true for non-expired lock' do
        lock = RailsCron::CronLock.new(
          key: 'test',
          acquired_at: Time.current,
          expires_at: Time.current + 60
        )
        expect(lock.not_expired?).to be(true)
      end

      it 'returns false for expired lock' do
        lock = RailsCron::CronLock.new(
          key: 'test',
          acquired_at: Time.current - 100,
          expires_at: Time.current - 10
        )
        expect(lock.not_expired?).to be(false)
      end
    end
  end

  describe 'thread safety' do
    it 'handles concurrent acquire calls safely' do
      key = 'test:concurrent:safety'
      results = []
      threads = []

      5.times do
        threads << Thread.new do
          result = adapter.acquire(key, 60)
          results << result
        end
      end

      threads.each(&:join)

      # Only one should succeed
      expect(results.count(true)).to eq(1)
      expect(results.count(false)).to eq(4)
    end
  end

  describe 'integration' do
    it 'complete workflow: acquire -> use -> release' do
      key = 'workflow:test'

      # Acquire
      acquired = adapter.acquire(key, 60)
      expect(acquired).to be(true)

      # Verify held
      second_attempt = adapter.acquire(key, 60)
      expect(second_attempt).to be(false)

      # Release
      released = adapter.release(key)
      expect(released).to be(true)

      # Can reacquire
      reacquired = adapter.acquire(key, 60)
      expect(reacquired).to be(true)

      # Cleanup
      adapter.release(key)
    end

    it 'works with coordinator workflow pattern' do
      cron_key = 'daily_report'
      fire_time = Time.current
      lock_key = "railscron:dispatch:#{cron_key}:#{fire_time.to_i}"

      # Coordinator would acquire lock
      acquired = adapter.acquire(lock_key, 60)
      expect(acquired).to be(true)

      # Dispatch work
      job_enqueued = true

      # Release lock after dispatch
      released = adapter.release(lock_key)
      expect(released).to be(true)
      expect(job_enqueued).to be(true)
    end
  end
end
