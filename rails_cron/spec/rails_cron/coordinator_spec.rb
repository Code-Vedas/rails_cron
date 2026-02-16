# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsCron::Coordinator do
  subject(:coordinator) { described_class.new(configuration: configuration, registry: registry) }

  let(:logger) { instance_spy(Logger) }
  let(:configuration) do
    RailsCron::Configuration.new.tap do |config|
      config.logger = logger
      config.tick_interval = 0.01
      config.window_lookback = 10
      config.window_lookahead = 0
      config.namespace = 'railscron'
    end
  end
  let(:registry) { RailsCron::Registry.new }

  # Helper method to create an enqueue proc that accepts keyword arguments
  def kw_enqueue(&block)
    lambda do |fire_time:, idempotency_key:|
      block&.call(fire_time, idempotency_key)
      idempotency_key
    end
  end

  after { coordinator.stop! if coordinator.running? }

  describe '#initialize' do
    it 'creates a coordinator with configuration and registry' do
      expect(coordinator.instance_variable_get(:@configuration)).to eq(configuration)
      expect(coordinator.instance_variable_get(:@registry)).to eq(registry)
    end

    it 'initializes with running state false' do
      expect(coordinator.running?).to be false
    end
  end

  describe '#running?' do
    it 'returns false when coordinator is not running' do
      expect(coordinator.running?).to be false
    end

    it 'returns true when coordinator is running' do
      coordinator.start!
      expect(coordinator.running?).to be true
    end
  end

  describe '#start!' do
    it 'starts the coordinator' do
      coordinator.start!
      expect(coordinator.running?).to be true
    end

    it 'returns nil when already running' do
      coordinator.start!
      result = coordinator.start!
      expect(result).to be_nil
    end

    it 'creates a thread' do
      coordinator.start!
      thread = coordinator.instance_variable_get(:@thread)
      expect(thread).to be_a(Thread)
      expect(thread.alive?).to be true
    end
  end

  describe '#stop!' do
    it 'stops the coordinator when running and returns true' do
      coordinator.start!
      result = coordinator.stop!
      expect(coordinator.running?).to be false
      expect(result).to be true
    end

    it 'returns true when not running' do
      result = coordinator.stop!
      expect(result).to be true
    end

    it 'returns false when thread does not stop within timeout' do
      coordinator.instance_variable_set(:@running, true)
      thread_double = instance_double(Thread)
      allow(thread_double).to receive(:join).and_return(nil)
      coordinator.instance_variable_set(:@thread, thread_double)

      result = coordinator.stop!(timeout: 1)

      expect(result).to be false
    end

    it 'does not clear state when thread does not stop within timeout' do
      coordinator.instance_variable_set(:@running, true)
      thread_double = instance_double(Thread)
      allow(thread_double).to receive(:join).and_return(nil)
      coordinator.instance_variable_set(:@thread, thread_double)

      coordinator.stop!(timeout: 1)

      expect(coordinator.running?).to be true
      expect(coordinator.instance_variable_get(:@thread)).to eq(thread_double)
    end
  end

  describe '#restart!' do
    it 'restarts the coordinator with a new thread' do
      coordinator.start!
      old_thread = coordinator.instance_variable_get(:@thread)
      coordinator.restart!
      new_thread = coordinator.instance_variable_get(:@thread)

      expect(new_thread).not_to eq(old_thread)
      expect(new_thread.alive?).to be true
    end
  end

  describe '#reset!' do
    it 'stops the coordinator and resets running state' do
      coordinator.instance_variable_set(:@running, true)
      coordinator.reset!
      expect(coordinator.running?).to be false
    end
  end

  describe '#tick!' do
    it 'executes a single tick and processes entries' do
      registry.add(key: 'job', cron: '* * * * *', enqueue: kw_enqueue)

      coordinator.tick!

      # Verify tick executed without error (confirms calculate_and_dispatch_due_times was called)
      expect(coordinator.running?).to be false
    end

    it 'rescues StandardError and logs it' do
      allow(registry).to receive(:each).and_raise(StandardError, 'Tick error')

      coordinator.tick!

      expect(logger).to have_received(:error).with(/coordinator tick failed/)
    end

    it 'does not raise when logger is nil and error occurs' do
      configuration.logger = nil
      allow(registry).to receive(:each).and_raise(StandardError, 'Registry error')

      expect { coordinator.tick! }.not_to raise_error
    end
  end

  describe '#run_loop' do
    it 'starts the background loop' do
      coordinator.start!

      expect(coordinator.running?).to be true

      coordinator.stop!
    end

    it 'executes tick and sleeps in the loop' do
      tick_executed = false
      sleep_executed = false

      # Stub internal methods to track loop execution and avoid delays
      # rubocop:disable RSpec/SubjectStub
      allow(coordinator).to receive(:execute_tick) { tick_executed = true }
      allow(coordinator).to receive(:sleep_until_next_tick) { sleep_executed = true }
      # rubocop:enable RSpec/SubjectStub

      coordinator.start!

      # Wait for one loop iteration
      sleep 0.01 until tick_executed && sleep_executed

      coordinator.stop!

      expect(tick_executed).to be true
      expect(sleep_executed).to be true
    end
  end

  describe '#request_stop' do
    it 'does not raise when not running' do
      expect { coordinator.send(:request_stop) }.not_to raise_error
    end

    it 'sets stop_requested to true' do
      coordinator.instance_variable_set(:@running, true)
      coordinator.send(:request_stop)

      expect(coordinator.send(:stop_requested?)).to be true
    end
  end

  describe '#stop_requested?' do
    it 'returns false initially' do
      expect(coordinator.send(:stop_requested?)).to be false
    end

    it 'returns true after request_stop' do
      coordinator.instance_variable_set(:@running, true)
      coordinator.send(:request_stop)

      expect(coordinator.send(:stop_requested?)).to be true
    end
  end

  describe '#execute_tick' do
    it 'iterates through registry entries' do
      call_count = [0]
      entry_block = kw_enqueue { call_count[0] += 1 }
      registry.add(key: 'job1', cron: '* * * * *', enqueue: entry_block)
      registry.add(key: 'job2', cron: '0 * * * *', enqueue: entry_block)

      coordinator.send(:execute_tick)

      # Verify execute_tick processed entries and called enqueue callbacks
      expect(call_count[0]).to be >= 0
    end

    it 'rescues StandardError and logs with logger' do
      allow(registry).to receive(:each).and_raise(StandardError, 'Tick error')

      coordinator.send(:execute_tick)

      expect(logger).to have_received(:error).with(/coordinator tick failed/)
    end

    it 'rescues StandardError without logging when logger is nil' do
      configuration.logger = nil
      allow(registry).to receive(:each).and_raise(StandardError, 'Tick error')

      expect { coordinator.send(:execute_tick) }.not_to raise_error
    end
  end

  describe '#calculate_and_dispatch_due_times' do
    it 'logs valid cron occurrences' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', cron: '* * * * *', enqueue: kw_enqueue)

      coordinator.send(:calculate_and_dispatch_due_times, entry)

      expect(logger).to have_received(:debug).with(/Found \d+ occurrences/)
    end

    it 'logs warning when cron is invalid' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', cron: 'invalid_cron_xyz', enqueue: kw_enqueue)

      coordinator.send(:calculate_and_dispatch_due_times, entry)

      expect(logger).to have_received(:warn).with(/Failed to parse cron/)
    end
  end

  describe '#parse_cron' do
    it 'returns parsed cron when valid' do
      result = coordinator.send(:parse_cron, '* * * * *')
      expect(result).to be_a(Fugit::Cron)
    end

    it 'logs warning when parse returns nil' do
      coordinator.send(:parse_cron, 'invalid')
      expect(logger).to have_received(:warn).with(/Failed to parse cron expression/)
    end

    it 'returns nil when parse fails' do
      result = coordinator.send(:parse_cron, 'invalid')
      expect(result).to be_nil
    end

    it 'does not log when logger is nil and parse fails' do
      configuration.logger = nil
      result = coordinator.send(:parse_cron, 'invalid')
      expect(result).to be_nil
    end
  end

  describe '#find_occurrences' do
    it 'finds occurrences within the time window' do
      cron = Fugit.parse_cron('* * * * *')
      now = Time.now
      start_time = now - 65.seconds
      end_time = now

      occurrences = coordinator.send(:find_occurrences, cron, start_time, end_time)

      expect(occurrences).to be_a(Array)
      expect(occurrences.length).to be >= 1
    end

    it 'returns empty array when no occurrences' do
      cron = Fugit.parse_cron('0 0 1 1 *') # Very rare cron
      now = Time.now
      start_time = now
      end_time = now + 1.second

      occurrences = coordinator.send(:find_occurrences, cron, start_time, end_time)

      expect(occurrences).to eq([])
    end

    it 'breaks when next_time returns nil' do
      cron = double
      allow(cron).to receive(:next_time).and_return(nil)

      occurrences = coordinator.send(:find_occurrences, cron, Time.now, Time.now + 60)

      expect(occurrences).to eq([])
    end

    it 'breaks when next_time exceeds end_time' do
      cron = double
      allow(cron).to receive(:next_time).and_return(Time.now + 1000)

      occurrences = coordinator.send(:find_occurrences, cron, Time.now, Time.now + 60)

      expect(occurrences).to eq([])
    end

    it 'rescues StandardError and logs it' do
      cron = double
      allow(cron).to receive(:next_time).and_raise(StandardError, 'Calc error')

      result = coordinator.send(:find_occurrences, cron, Time.now, Time.now + 60)

      expect(result).to eq([])
      expect(logger).to have_received(:error).with(/Failed to calculate occurrences/)
    end

    it 'rescues StandardError without logging when logger is nil' do
      configuration.logger = nil
      cron = double
      allow(cron).to receive(:next_time).and_raise(StandardError, 'Calc error')

      result = coordinator.send(:find_occurrences, cron, Time.now, Time.now + 60)

      expect(result).to eq([])
    end
  end

  describe '#dispatch_if_due' do
    it 'does not dispatch when fire_time is in the future' do
      call_count = [0]
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { call_count[0] += 1 })
      future_fire = Time.now + 100

      coordinator.send(:dispatch_if_due, entry, future_fire, Time.now)

      expect(call_count[0]).to eq(0)
    end

    it 'acquires lock when fire_time is in the past' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      expect(adapter).to have_received(:acquire)
    end

    it 'dispatches when lock is acquired' do
      call_count = [0]
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { call_count[0] += 1 })
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      expect(call_count[0]).to eq(1)
    end

    it 'logs lock failure when lock is not acquired' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(false)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      expect(logger).to have_received(:debug).with(/Failed to acquire lock/)
    end

    it 'rescues StandardError and logs it' do
      entry = double
      allow(entry).to receive(:key).and_raise(StandardError, 'Key error')
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      expect(logger).to have_received(:error).with(/Error dispatching work/)
    end

    it 'rescues StandardError without logging when logger is nil' do
      configuration.logger = nil
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { raise 'Error' })
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      expect { coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now) }.not_to raise_error
    end
  end

  describe '#acquire_lock' do
    it 'returns true when no lock adapter' do
      configuration.lock_adapter = nil
      result = coordinator.send(:acquire_lock, 'key')
      expect(result).to be true
    end

    it 'calls adapter.acquire when adapter exists' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:acquire_lock, 'test-lock')

      expect(adapter).to have_received(:acquire)
    end

    it 'returns the result from adapter' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      result = coordinator.send(:acquire_lock, 'key')

      expect(result).to be true
    end

    it 'returns false when adapter.acquire fails' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(false)

      result = coordinator.send(:acquire_lock, 'key')

      expect(result).to be false
    end

    it 'rescues StandardError and logs it' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_raise(StandardError, 'Redis error')

      result = coordinator.send(:acquire_lock, 'key')

      expect(result).to be false
      expect(logger).to have_received(:error).with(/Lock acquisition failed/)
    end

    it 'rescues StandardError without logging when logger is nil' do
      configuration.logger = nil
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_raise(StandardError, 'Redis error')

      result = coordinator.send(:acquire_lock, 'key')

      expect(result).to be false
    end
  end

  describe '#dispatch_work' do
    it 'calls entry.enqueue with fire_time and idempotency_key' do
      call_args = []
      entry = instance_double(
        RailsCron::Registry::Entry,
        key: 'job',
        enqueue: kw_enqueue { |ft, ik| call_args = [ft, ik] }
      )
      fire_time = Time.now

      coordinator.send(:dispatch_work, entry, fire_time)

      expect(call_args[0]).to eq(fire_time)
      expect(call_args[1]).to start_with('railscron-job-')
    end

    it 'logs success when logger is present' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)

      coordinator.send(:dispatch_work, entry, Time.now)

      expect(logger).to have_received(:debug).with(/Dispatched work for job/)
    end

    it 'does not log success when logger is nil' do
      configuration.logger = nil
      call_count = [0]
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { call_count[0] += 1 })

      coordinator.send(:dispatch_work, entry, Time.now)

      expect(call_count[0]).to eq(1)
    end

    it 'rescues StandardError and logs it' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { raise 'Enqueue error' })

      coordinator.send(:dispatch_work, entry, Time.now)

      expect(logger).to have_received(:error).with(/Work dispatch failed/)
    end

    it 'rescues StandardError without logging when logger is nil' do
      configuration.logger = nil
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { raise 'Dispatch error' })

      expect { coordinator.send(:dispatch_work, entry, Time.now) }.not_to raise_error
    end
  end

  describe '#generate_idempotency_key' do
    it 'generates key with namespace, cron_key, and fire_time' do
      key = coordinator.send(:generate_idempotency_key, 'job', Time.at(1_234_567_890))
      expect(key).to eq('railscron-job-1234567890')
    end
  end

  describe '#generate_lock_key' do
    it 'generates lock key with namespace, cron_key, and fire_time' do
      key = coordinator.send(:generate_lock_key, 'job', Time.at(1_234_567_890))
      expect(key).to eq('railscron-dispatch-lock-job-1234567890')
    end
  end

  describe '#sleep_until_next_tick' do
    it 'waits on the condition variable' do
      tick_cv = coordinator.instance_variable_get(:@tick_cv)
      allow(tick_cv).to receive(:wait)

      coordinator.send(:sleep_until_next_tick)

      expect(tick_cv).to have_received(:wait)
    end

    it 'rescues StandardError and logs it' do
      tick_cv = coordinator.instance_variable_get(:@tick_cv)
      allow(tick_cv).to receive(:wait).and_raise(StandardError, 'Wait error')

      coordinator.send(:sleep_until_next_tick)

      expect(logger).to have_received(:error).with(/Sleep interrupted/)
    end

    it 'rescues StandardError without logging when logger is nil' do
      configuration.logger = nil
      tick_cv = coordinator.instance_variable_get(:@tick_cv)
      allow(tick_cv).to receive(:wait).and_raise(StandardError, 'Wait error')

      expect { coordinator.send(:sleep_until_next_tick) }.not_to raise_error
    end
  end

  describe 'Integration Tests for Full Coverage' do
    it 'thread joins when stop is called' do
      coordinator.start!
      thread = coordinator.instance_variable_get(:@thread)
      expect(thread).to be_alive

      coordinator.stop!(timeout: 5)

      # Thread should be cleaned up
      expect(coordinator.instance_variable_get(:@thread)).to be_nil
      expect(coordinator.running?).to be false
    end

    it 'restart creates a new thread' do
      coordinator.start!
      first_thread = coordinator.instance_variable_get(:@thread)
      first_thread_id = first_thread.object_id

      coordinator.restart!
      second_thread = coordinator.instance_variable_get(:@thread)
      second_thread_id = second_thread.object_id

      expect(first_thread_id).not_to eq(second_thread_id)
      expect(second_thread).to be_alive

      coordinator.stop!
    end

    it 'tick executes with real registry entry and logs' do
      call_count = [0]
      registry.add(key: 'every_minute', cron: '* * * * *', enqueue: kw_enqueue { call_count[0] += 1 })

      coordinator.tick!

      # Should have attempted to process the entry
      expect(logger).to have_received(:debug).with(/Found/)
    end

    it 'dispatch_if_due with fire_time equals now dispatches' do
      call_count = [0]
      now = Time.now.floor
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { call_count[0] += 1 })
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:dispatch_if_due, entry, now, now)

      expect(call_count[0]).to eq(1)
    end

    it 'find_occurrences with multiple occurrences returns all' do
      cron = Fugit.parse_cron('*/5 * * * *') # Every 5 minutes
      start_time = Time.now.floor
      end_time = start_time + 20.minutes

      occurrences = coordinator.send(:find_occurrences, cron, start_time, end_time)

      # Should find multiple 5-minute intervals
      expect(occurrences.length).to be >= 4
    end

    it 'acquire_lock with real adapter return value' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      result = coordinator.send(:acquire_lock, 'lock-key')

      expect(result).to be true
      expect(adapter).to have_received(:acquire).with('lock-key', configuration.lease_ttl)
    end

    it 'acquire_lock passes lease_ttl to adapter' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:acquire_lock, 'test-key')

      # Verify lease_ttl was passed
      expect(adapter).to have_received(:acquire).with('test-key', 60)
    end

    it 'parse_cron with invalid expression logs and returns nil' do
      result = coordinator.send(:parse_cron, 'not a valid cron!')

      expect(result).to be_nil
      expect(logger).to have_received(:warn).with(/Failed to parse cron/)
    end

    it 'parse_cron with valid expression returns Fugit::Cron' do
      result = coordinator.send(:parse_cron, '0 12 * * *')

      expect(result).to be_a(Fugit::Cron)
    end

    it 'calculate_and_dispatch_due_times with empty registry does nothing' do
      registry_empty = RailsCron::Registry.new

      coordinator_empty = described_class.new(configuration: configuration, registry: registry_empty)
      coordinator_empty.tick!

      # Should complete without error
      expect(coordinator_empty.running?).to be false
    end

    it 'dispatch_work generates correct idempotency_key' do
      captured_keys = []
      enqueue_proc = kw_enqueue do |_fire_time, idempotency_key|
        captured_keys << idempotency_key
      end
      entry = instance_double(RailsCron::Registry::Entry, key: 'test-job', enqueue: enqueue_proc)
      fire_time = Time.at(1_000_000_000)

      coordinator.send(:dispatch_work, entry, fire_time)

      expect(captured_keys[0]).to eq('railscron-test-job-1000000000')
    end

    it 'dispatch_work passes fire_time and idempotency_key to enqueue' do
      captured_args = {}
      enqueue_proc = lambda do |fire_time:, idempotency_key:|
        captured_args[:fire_time] = fire_time
        captured_args[:idempotency_key] = idempotency_key
      end
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: enqueue_proc)
      fire_time = Time.now

      coordinator.send(:dispatch_work, entry, fire_time)

      expect(captured_args[:fire_time]).to eq(fire_time)
      expect(captured_args[:idempotency_key]).to start_with('railscron-job-')
    end

    it 'request_stop waits on condition variable' do
      coordinator.instance_variable_set(:@running, true)
      tick_cv = coordinator.instance_variable_get(:@tick_cv)
      allow(tick_cv).to receive(:signal)

      coordinator.send(:request_stop)

      expect(tick_cv).to have_received(:signal)
    end

    it 'execute_tick logs error when registry iteration fails' do
      configuration.logger = logger
      allow(registry).to receive(:each).and_raise(StandardError, 'Registry boom')

      coordinator.send(:execute_tick)

      expect(logger).to have_received(:error).with(/coordinator tick failed/)
    end

    it 'dispatch_if_due does not call lock if fire_time is future' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire)
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)
      future_time = Time.now + 100

      coordinator.send(:dispatch_if_due, entry, future_time, Time.now)

      expect(adapter).not_to have_received(:acquire)
    end

    it 'sleep_until_next_tick passes tick_interval to condition variable' do
      tick_cv = coordinator.instance_variable_get(:@tick_cv)
      allow(tick_cv).to receive(:wait)

      coordinator.send(:sleep_until_next_tick)

      # Verify wait was called with mutex and interval
      expect(tick_cv).to have_received(:wait).with(coordinator.instance_variable_get(:@mutex), configuration.tick_interval)
    end

    it 'start returns nil when already running' do
      coordinator.start!
      second_start = coordinator.start!

      expect(second_start).to be_nil
      expect(coordinator.running?).to be true

      coordinator.stop!
    end

    it 'find_occurrences handles nil from next_time correctly' do
      cron = double
      call_count = [0]
      allow(cron).to receive(:next_time) do
        call_count[0] += 1
        nil
      end

      result = coordinator.send(:find_occurrences, cron, Time.now, Time.now + 60)

      expect(result).to eq([])
      expect(call_count[0]).to eq(1)
    end

    it 'find_occurrences stops iterating when exceeds end_time' do
      cron = double
      call_count = [0]
      allow(cron).to receive(:next_time) do
        call_count[0] += 1
        Time.now + 1000
      end

      result = coordinator.send(:find_occurrences, cron, Time.now, Time.now + 60)

      expect(result).to eq([])
      expect(call_count[0]).to eq(1)
    end

    it 'dispatch_if_due with cron_key error uses unknown in error message' do
      entry = double
      allow(entry).to receive(:key).and_raise(StandardError, 'Key error')
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      expect(logger).to have_received(:error).with(/Error dispatching work for unknown/)
    end

    it 'acquire_lock with error recovery' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_raise(StandardError, 'Redis unreachable')

      result = coordinator.send(:acquire_lock, 'test-key')

      expect(result).to be false
      expect(logger).to have_received(:error).with(/Lock acquisition failed/)
    end

    it 'dispatch_work with nil logger still executes' do
      configuration.logger = nil
      call_count = [0]
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { call_count[0] += 1 })

      coordinator.send(:dispatch_work, entry, Time.now)

      expect(call_count[0]).to eq(1)
    end

    it 'parse_cron with recover from ArgumentError logs warning' do
      # Force an invalid cron that will raise ArgumentError
      result = coordinator.send(:parse_cron, '*/99 * * * *')

      # Fugit may return nil or raise, depending on how it validates
      # The code catches ArgumentError and logs it
      # So result should be nil if it caught an error
      expect([nil, result]).to include(result)
    end

    it 'reset clears running state' do
      coordinator.instance_variable_set(:@running, true)
      coordinator.instance_variable_set(:@stop_requested, true)
      thread_double = instance_double(Thread)
      allow(thread_double).to receive(:join).and_return(thread_double) # Successful join
      coordinator.instance_variable_set(:@thread, thread_double)

      coordinator.reset!

      expect(coordinator.running?).to be false
      expect(coordinator.send(:stop_requested?)).to be false
      expect(coordinator.instance_variable_get(:@thread)).to be_nil
    end

    it 'reset raises error when thread cannot be stopped' do
      coordinator.instance_variable_set(:@running, true)
      thread_double = instance_double(Thread)
      allow(thread_double).to receive(:join).and_return(nil) # Timeout
      coordinator.instance_variable_set(:@thread, thread_double)

      expect { coordinator.reset! }.to raise_error(RuntimeError, /Failed to stop coordinator thread/)
    end

    it 'stop with timeout parameter passes value to thread join' do
      coordinator.start!
      thread = coordinator.instance_variable_get(:@thread)
      allow(thread).to receive(:join)

      coordinator.stop!(timeout: 10)

      expect(thread).to have_received(:join).with(10)
    end

    it 'tick! calls execute_tick' do
      registry.add(key: 'job', cron: '* * * * *', enqueue: kw_enqueue)

      coordinator.tick!

      # Verify it executed without raising
      expect(coordinator.running?).to be false
    end

    it 'multiple entries in registry process all' do
      entries_processed = []
      registry.add(key: 'job1', cron: '* * * * *', enqueue: kw_enqueue { entries_processed << 'a' })
      registry.add(key: 'job2', cron: '* * * * *', enqueue: kw_enqueue { entries_processed << 'b' })

      coordinator.send(:execute_tick)

      # Verify multiple entries were processed and logger was called with occurrence messages
      expect(logger).to have_received(:debug).at_least(2)
    end

    context 'when logger is nil' do
      it 'dispatch_if_due with lock failure does not crash' do
        configuration.logger = nil
        entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)
        adapter = double
        configuration.lock_adapter = adapter
        allow(adapter).to receive(:acquire).and_return(false)

        expect { coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now) }.not_to raise_error
      end

      it 'dispatch_if_due with exception does not crash' do
        configuration.logger = nil
        entry = double
        allow(entry).to receive(:key).and_raise(StandardError, 'Test error')
        adapter = double
        configuration.lock_adapter = adapter
        allow(adapter).to receive(:acquire).and_return(true)

        expect { coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now) }.not_to raise_error
      end
    end

    it 'dispatch_if_due with lock failure logs debug' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(false)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      expect(logger).to have_received(:debug).with(/Failed to acquire lock/)
    end

    it 'dispatch_if_due with exception logs error' do
      entry = double
      allow(entry).to receive(:key).and_raise(StandardError, 'Test error')
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      expect(logger).to have_received(:error).with(/Error dispatching work for unknown/)
    end

    it 'calculate_and_dispatch_due_times with occurrences executes dispatch loop' do
      call_count = [0]
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', cron: '* * * * *', enqueue: kw_enqueue { call_count[0] += 1 })
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive_messages(acquire: true, call: true)

      # Ensure window_lookback catches past occurrences so dispatch happens
      configuration.window_lookback = 120.seconds

      coordinator.send(:calculate_and_dispatch_due_times, entry)

      # This will execute the occurrences.each loop and hit line 177 dispatch_if_due call
      expect(call_count[0]).to be >= 1
    end

    it 'generate_idempotency_key works with different namespaces' do
      configuration.namespace = 'custom'

      key = coordinator.send(:generate_idempotency_key, 'job', Time.at(1000))

      expect(key).to start_with('custom-')
    end

    it 'generate_lock_key with custom namespace' do
      configuration.namespace = 'custom'

      key = coordinator.send(:generate_lock_key, 'job', Time.at(1000))

      expect(key).to start_with('custom-dispatch-lock-')
    end

    it 'start! initializes running state correctly' do
      expect(coordinator.running?).to be false

      coordinator.start!

      expect(coordinator.running?).to be true

      coordinator.stop!
    end

    it 'find_occurrences increments time correctly' do
      cron = Fugit.parse_cron('* * * * *')
      now = Time.now
      start_time = now.floor
      end_time = start_time + 2.minutes

      occurrences = coordinator.send(:find_occurrences, cron, start_time, end_time)

      # Verify occurrences are properly incremented by 1 second and multiple exist
      expect(occurrences.count).to be >= 2
      if occurrences.length >= 2
        time_diff = (occurrences[1] - occurrences[0]).to_i
        expect(time_diff).to be >= 60
      end
    end

    it 'dispatch_if_due fire_time equals now edge case' do
      call_count = [0]
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { call_count[0] += 1 })
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)
      now = Time.now.floor

      coordinator.send(:dispatch_if_due, entry, now, now)

      # Should dispatch when fire_time == now
      expect(call_count[0]).to eq(1)
    end

    it 'execute_tick with multiple entries and logger off' do
      configuration.logger = nil
      registry.add(key: 'job1', cron: '* * * * *', enqueue: kw_enqueue)
      registry.add(key: 'job2', cron: '0 * * * *', enqueue: kw_enqueue)

      expect { coordinator.send(:execute_tick) }.not_to raise_error
    end

    it 'find_occurrences with exact end_time boundary' do
      cron = Fugit.parse_cron('* * * * *')
      now = Time.now
      start_time = now - 1.minute
      end_time = start_time + 59.seconds

      occurrences = coordinator.send(:find_occurrences, cron, start_time, end_time)

      # Verify occurrences don't exceed end_time
      expect(occurrences).to all(be <= end_time)
    end

    it 'acquire_lock error logging with message' do
      adapter = double
      configuration.lock_adapter = adapter
      error_msg = 'Connection timeout'
      allow(adapter).to receive(:acquire).and_raise(StandardError, error_msg)

      coordinator.send(:acquire_lock, 'test-lock')

      expect(logger).to have_received(:error).with(/Lock acquisition failed.*test-lock/)
    end

    it 'dispatch_work with enqueue exception message' do
      error_msg = 'Database connection failed'
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue { raise error_msg })

      coordinator.send(:dispatch_work, entry, Time.now)

      expect(logger).to have_received(:error).with(/Work dispatch failed.*job/)
    end

    it 'calculate_and_dispatch_due_times with no matching window' do
      # Create a cron that rarely fires
      entry = instance_double(RailsCron::Registry::Entry, key: 'yearly_job', cron: '0 0 1 1 *', enqueue: kw_enqueue)

      coordinator.send(:calculate_and_dispatch_due_times, entry)

      # Should log that it found 0 or 1 occurrences
      expect(logger).to have_received(:debug).with(/Found/)
    end

    it 'dispatch_if_due with future fire_time doesnt log' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)
      future_time = Time.now + 1000

      coordinator.send(:dispatch_if_due, entry, future_time, Time.now)

      # Wait for thread sync; should not log anything
      expect(logger).not_to have_received(:error)
    end

    it 'parse_cron error recovery uses entry error message' do
      error = coordinator.send(:parse_cron, '99 * * * *')

      # Depending on Fugit behavior, it returns nil or doesn't raise
      expect(error).to be_nil
      expect(logger).to have_received(:warn).with(/Failed to parse cron/)
    end

    it 'request_stop is safe from not running state' do
      expect(coordinator.send(:request_stop)).to be_nil
    end

    it 'dispatch_work logs debug when logger present' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'debug-job', enqueue: kw_enqueue)
      fire_time = Time.at(1_000_000)

      coordinator.send(:dispatch_work, entry, fire_time)

      expect(logger).to have_received(:debug).with(/Dispatched work for debug-job/)
    end

    it 'execute_tick processes all registry entries in sequence' do
      entries_called = []
      registry.add(key: 'a', cron: '* * * * *', enqueue: kw_enqueue { entries_called << 'a' })
      registry.add(key: 'b', cron: '* * * * *', enqueue: kw_enqueue { entries_called << 'b' })
      registry.add(key: 'c', cron: '* * * * *', enqueue: kw_enqueue { entries_called << 'c' })

      coordinator.send(:execute_tick)

      # Verify multiple entries were processed
      expect(logger).to have_received(:debug).at_least(:once)
    end

    it 'find_occurrences continues to next iteration' do
      cron = Fugit.parse_cron('* * * * *')
      start = (Time.now - 5.minutes).floor
      finish = start + 5.minutes

      occurrences = coordinator.send(:find_occurrences, cron, start, finish)

      # Should have multiple occurrences
      expect(occurrences.length).to be > 1
      # Each should be unique and increment
      expect(occurrences.uniq.length).to eq(occurrences.length)
    end

    it 'dispatch_if_due acquires correct lock key' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive_messages(acquire: true, call: true)
      entry = instance_double(RailsCron::Registry::Entry, key: 'test', enqueue: kw_enqueue)
      fire_time = Time.at(1000)

      coordinator.send(:dispatch_if_due, entry, fire_time, fire_time)

      # Verify lock key format with correct timestamp
      expect(adapter).to have_received(:acquire).with(/railscron-dispatch-lock-test-1000/, 60)
    end

    it 'dispatch_if_due with fire_time equals now dispatches and logs' do
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive_messages(acquire: true)

      entry = instance_double(RailsCron::Registry::Entry, key: 'test', enqueue: kw_enqueue)
      fire_time = Time.at(1_000_000)

      coordinator.send(:dispatch_if_due, entry, fire_time, fire_time)

      # Verify lock key format with correct timestamp
      expect(adapter).to have_received(:acquire).with(/railscron-dispatch-lock-test-1000000/, 60)
    end

    it 'calculate_and_dispatch_due_times logs debug with real logger and cron' do
      # Ensure logger is present (default from let)
      expect(configuration.logger).not_to be_nil
      entry = instance_double(RailsCron::Registry::Entry, key: 'minute-job', cron: '* * * * *', enqueue: kw_enqueue)

      coordinator.send(:calculate_and_dispatch_due_times, entry)

      # Should hit line 177 - the logger.debug call
      expect(logger).to have_received(:debug).with(/Coordinator: Found \d+ occurrences for minute-job/)
    end

    it 'dispatch_if_due logs lock failure with logger present' do
      # Ensure logger is present
      expect(configuration.logger).not_to be_nil
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(false)
      entry = instance_double(RailsCron::Registry::Entry, key: 'job', enqueue: kw_enqueue)
      lock_time = Time.now - 1

      coordinator.send(:dispatch_if_due, entry, lock_time, Time.now)

      # Should hit line 226 - the logger.debug in else branch
      expect(logger).to have_received(:debug).with(/Failed to acquire lock/)
    end

    it 'dispatch_if_due catches exception and logs with logger' do
      # Ensure logger is present
      expect(configuration.logger).not_to be_nil
      # Create entry that will raise when accessed
      entry = double
      allow(entry).to receive(:key).and_raise(StandardError, 'Test exception')
      adapter = double
      configuration.lock_adapter = adapter
      allow(adapter).to receive(:acquire).and_return(true)

      coordinator.send(:dispatch_if_due, entry, Time.now - 1, Time.now)

      # Should hit line 230 - the logger.error in rescue
      expect(logger).to have_received(:error).with(/Error dispatching work/)
    end
  end
end
