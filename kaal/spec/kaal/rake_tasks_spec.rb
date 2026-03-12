# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'rake'
require 'stringio'

RSpec.describe Kaal::RakeTasks do
  let(:rake) { Rake::Application.new }

  before do
    Rake.application = rake
    rake.define_task(Rake::Task, :environment)
    described_class.install(rake)
  end

  after do
    Rake.application = nil
  end

  def task(name)
    rake[name]
  end

  describe 'kaal:tick' do
    it 'runs a single tick and prints success' do
      allow(Kaal).to receive(:tick!)

      expect { task('kaal:tick').invoke }.to output(/tick completed/).to_stdout
      expect(Kaal).to have_received(:tick!)
    end

    it 'aborts on errors' do
      allow(Kaal).to receive(:tick!).and_raise(StandardError, 'boom')

      expect { task('kaal:tick').invoke }
        .to raise_error(SystemExit)
        .and output(/kaal:tick failed: boom/).to_stderr
    end
  end

  describe 'kaal:status' do
    it 'prints scheduler state and registered jobs' do
      entry = instance_double(Kaal::Registry::Entry, key: 'reports:daily', cron: '0 9 * * *')
      allow(Kaal).to receive_messages(
        running?: false,
        tick_interval: 5,
        window_lookback: 120,
        window_lookahead: 0,
        lease_ttl: 125,
        namespace: 'railscron',
        registered: [entry]
      )

      output = capture_stdout { task('kaal:status').invoke }
      expect(output).to include('Kaal v')
      expect(output).to include('Running: false')
      expect(output).to include('Registered jobs: 1')
      expect(output).to include('reports:daily')
    end

    it 'aborts on errors' do
      allow(Kaal).to receive(:running?).and_raise(StandardError, 'boom')

      expect { task('kaal:status').invoke }
        .to raise_error(SystemExit)
        .and output(/Kaal v/).to_stdout
        .and output(/kaal:status failed: boom/).to_stderr
    end
  end

  describe 'kaal:explain' do
    it 'prints humanized cron text' do
      allow(Kaal).to receive(:to_human).with('*/5 * * * *').and_return('Every 5 minutes')

      expect { task('kaal:explain').invoke('*/5 * * * *') }.to output("Every 5 minutes\n").to_stdout
    end

    it 'aborts when expression argument is missing' do
      expect { task('kaal:explain').invoke }
        .to raise_error(SystemExit)
        .and output(/kaal:explain requires expr argument/).to_stderr
    end

    it 'aborts with invalid cron expressions' do
      allow(Kaal).to receive(:to_human).and_raise(ArgumentError, 'Invalid cron expression')

      expect { task('kaal:explain').invoke('bad') }
        .to raise_error(SystemExit)
        .and output(/kaal:explain failed: Invalid cron expression/).to_stderr
    end
  end

  describe 'kaal:start' do
    let(:captured_signal_handlers) { {} }
    let(:previous_handler_calls) { [] }
    let(:previous_handlers) do
      {
        'TERM' => proc { previous_handler_calls << 'TERM' },
        'INT' => proc { previous_handler_calls << 'INT' }
      }
    end

    before do
      allow(Signal).to receive(:trap) do |signal, handler = nil, &block|
        if handler == 'IGNORE'
          previous_handlers.fetch(signal, 'DEFAULT')
        elsif block
          captured_signal_handlers[signal] = block
          nil
        elsif !handler.nil?
          nil
        end
      end
    end

    it 'starts scheduler in foreground and joins thread' do
      thread = instance_double(Thread, join: nil)
      allow(Kaal).to receive(:start!).and_return(thread)

      expect { task('kaal:start').invoke }.to output(/started in foreground/).to_stdout
      expect(thread).to have_received(:join)
    end

    it 'aborts when scheduler is already running' do
      allow(Kaal).to receive(:start!).and_return(nil)

      expect { task('kaal:start').invoke }
        .to raise_error(SystemExit)
        .and output(/kaal:start failed: scheduler is already running/).to_stderr
    end

    it 'handles interrupts by stopping scheduler' do
      thread = instance_double(Thread)
      allow(thread).to receive(:join).and_raise(Interrupt)
      allow(Kaal).to receive(:start!).and_return(thread)
      allow(Kaal).to receive(:stop!).with(timeout: 30).and_return(true)

      expect { task('kaal:start').invoke }.to output(/Received INT.*scheduler stopped/m).to_stdout
      expect(Kaal).to have_received(:stop!).with(timeout: 30)
    end

    it 'handles TERM by stopping scheduler gracefully' do
      thread = instance_double(Thread)
      allow(Kaal).to receive(:start!).and_return(thread)
      allow(Kaal).to receive(:stop!).with(timeout: 30).and_return(true)

      allow(thread).to receive(:join) do
        captured_signal_handlers.fetch('TERM').call
      end

      expect { task('kaal:start').invoke }.to output(/Received TERM.*scheduler stopped/m).to_stdout
      expect(Kaal).to have_received(:stop!).with(timeout: 30).once
      expect(previous_handler_calls).to include('TERM')
    end

    it 'stops only once when multiple signals are received' do
      thread = instance_double(Thread)
      allow(Kaal).to receive(:start!).and_return(thread)
      allow(Kaal).to receive(:stop!).with(timeout: 30).and_return(true)

      allow(thread).to receive(:join) do
        captured_signal_handlers.fetch('TERM').call
        captured_signal_handlers.fetch('INT').call
      end

      expect { task('kaal:start').invoke }.to output(/Received TERM.*scheduler stopped/m).to_stdout

      expect(Kaal).to have_received(:stop!).with(timeout: 30).once
      expect(previous_handler_calls).to include('TERM', 'INT')
    end

    it 'forces task termination after a second signal when graceful stop times out' do
      thread = instance_double(Thread)
      allow(Kaal).to receive(:start!).and_return(thread)
      allow(Kaal).to receive(:stop!).with(timeout: 30).and_return(false)
      first_signal_processed = Queue.new
      release_second_signal = Queue.new

      allow(thread).to receive(:join) do
        signal_thread = Thread.new do
          captured_signal_handlers.fetch('TERM').call
          first_signal_processed << true
          release_second_signal.pop
          captured_signal_handlers.fetch('INT').call
        end
        first_signal_processed.pop
        release_second_signal << true
        Queue.new.pop
      ensure
        signal_thread&.join(0.1)
      end

      expect { task('kaal:start').invoke }
        .to raise_error(SystemExit)
        .and output(%r{stop timed out; send TERM/INT again to force exit.*forcing scheduler shutdown.*shutdown timed out; forced exit requested}m).to_stderr
        .and output(/started in foreground.*Received TERM, stopping Kaal scheduler/m).to_stdout
      expect(Kaal).to have_received(:stop!).with(timeout: 30).once
    end

    it 'aborts when start raises unexpected errors' do
      allow(Kaal).to receive(:start!).and_raise(StandardError, 'boom')

      expect { task('kaal:start').invoke }
        .to raise_error(SystemExit)
        .and output(/kaal:start failed: boom/).to_stderr
    end

    it 'handles interrupt raised before scheduler thread starts' do
      allow(Kaal).to receive(:start!).and_raise(Interrupt)
      allow(Kaal).to receive(:stop!).with(timeout: 30).and_return(true)

      expect { task('kaal:start').invoke }
        .to output(/Received INT, stopping Kaal scheduler.*Kaal scheduler stopped/m).to_stdout
      expect(Kaal).to have_received(:stop!).with(timeout: 30).once
    end
  end

  describe '.restore_signal_handlers' do
    it 'swallows errors when restoring handlers fails' do
      allow(Signal).to receive(:trap).and_raise(StandardError, 'trap restore failure')

      expect { described_class.restore_signal_handlers('TERM' => 'DEFAULT') }.not_to raise_error
    end
  end

  describe '.shutdown_scheduler' do
    it 'logs warning to stderr when stop raises' do
      signal_state = {
        graceful_shutdown_started: false,
        shutdown_complete: false,
        force_exit_requested: false
      }
      allow(Kaal).to receive(:stop!).and_raise(StandardError, 'stop blew up')

      expect do
        described_class.shutdown_scheduler(signal: 'TERM', signal_state: signal_state)
      end.to output(/Received TERM, stopping Kaal scheduler/).to_stdout
                                                             .and output(/shutdown failed: stop blew up/).to_stderr
    end

    it 'marks force exit and raises interrupt on second signal after timeout' do
      signal_state = {
        graceful_shutdown_started: false,
        shutdown_complete: false,
        force_exit_requested: false
      }
      allow(Kaal).to receive(:stop!).with(timeout: 30).and_return(false)

      expect do
        described_class.shutdown_scheduler(signal: 'TERM', signal_state: signal_state)
      end.to output(/Received TERM, stopping Kaal scheduler/).to_stdout
                                                             .and output(%r{stop timed out; send TERM/INT again to force exit}).to_stderr

      expect do
        described_class.shutdown_scheduler(signal: 'INT', signal_state: signal_state)
      end.to raise_error(Interrupt).and output(/forcing scheduler shutdown/).to_stderr
      expect(signal_state[:force_exit_requested]).to be(true)
    end
  end

  describe '.chain_previous_handler' do
    it 'warns when previous handler is a command string' do
      expect do
        described_class.chain_previous_handler('TERM', 'custom_handler')
      end.to output(/previous TERM handler is a command: custom_handler/).to_stderr
    end

    it 'swallows errors raised by previous callable handlers' do
      crashing_handler = proc { raise StandardError, 'previous crash' }

      expect do
        described_class.chain_previous_handler('INT', crashing_handler)
      end.not_to raise_error
    end

    it 'supports previous method handlers' do
      method_handler = 'scheduler'.method(:upcase)

      expect do
        described_class.chain_previous_handler('TERM', method_handler)
      end.not_to raise_error
    end

    it 'passes signal number to handlers expecting arguments' do
      received = nil
      handler = proc { |signo| received = signo }

      described_class.chain_previous_handler('TERM', handler)

      expect(received).to eq(Signal.list['TERM'])
    end

    it 'calls zero-arity handlers without arguments' do
      called = false
      handler = proc { called = true }

      described_class.chain_previous_handler('INT', handler)

      expect(called).to be(true)
    end

    it 'does not warn for DEFAULT or IGNORE handlers' do
      expect do
        described_class.chain_previous_handler('TERM', 'DEFAULT')
        described_class.chain_previous_handler('TERM', 'IGNORE')
        described_class.chain_previous_handler('TERM', 'SYSTEM_DEFAULT')
        described_class.chain_previous_handler('TERM', 'EXIT')
      end.not_to output.to_stderr
    end

    it 'ignores unsupported previous handler types' do
      expect do
        described_class.chain_previous_handler('TERM', 42)
      end.not_to output.to_stderr
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
