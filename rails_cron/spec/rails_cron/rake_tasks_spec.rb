# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'rake'
require 'stringio'

RSpec.describe RailsCron::RakeTasks do
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

  describe 'rails_cron:tick' do
    it 'runs a single tick and prints success' do
      allow(RailsCron).to receive(:tick!)

      expect { task('rails_cron:tick').invoke }.to output(/tick completed/).to_stdout
      expect(RailsCron).to have_received(:tick!)
    end

    it 'aborts on errors' do
      allow(RailsCron).to receive(:tick!).and_raise(StandardError, 'boom')

      expect { task('rails_cron:tick').invoke }
        .to raise_error(SystemExit)
        .and output(/rails_cron:tick failed: boom/).to_stderr
    end
  end

  describe 'rails_cron:status' do
    it 'prints scheduler state and registered jobs' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'reports:daily', cron: '0 9 * * *')
      allow(RailsCron).to receive_messages(
        running?: false,
        tick_interval: 5,
        window_lookback: 120,
        window_lookahead: 0,
        lease_ttl: 125,
        namespace: 'railscron',
        registered: [entry]
      )

      output = capture_stdout { task('rails_cron:status').invoke }
      expect(output).to include('RailsCron v')
      expect(output).to include('Running: false')
      expect(output).to include('Registered jobs: 1')
      expect(output).to include('reports:daily')
    end

    it 'aborts on errors' do
      allow(RailsCron).to receive(:running?).and_raise(StandardError, 'boom')

      expect { task('rails_cron:status').invoke }
        .to raise_error(SystemExit)
        .and output(/RailsCron v/).to_stdout
        .and output(/rails_cron:status failed: boom/).to_stderr
    end
  end

  describe 'rails_cron:explain' do
    it 'prints humanized cron text' do
      allow(RailsCron).to receive(:to_human).with('*/5 * * * *').and_return('Every 5 minutes')

      expect { task('rails_cron:explain').invoke('*/5 * * * *') }.to output("Every 5 minutes\n").to_stdout
    end

    it 'aborts when expression argument is missing' do
      expect { task('rails_cron:explain').invoke }
        .to raise_error(SystemExit)
        .and output(/rails_cron:explain requires expr argument/).to_stderr
    end

    it 'aborts with invalid cron expressions' do
      allow(RailsCron).to receive(:to_human).and_raise(ArgumentError, 'Invalid cron expression')

      expect { task('rails_cron:explain').invoke('bad') }
        .to raise_error(SystemExit)
        .and output(/rails_cron:explain failed: Invalid cron expression/).to_stderr
    end
  end

  describe 'rails_cron:start' do
    let(:captured_signal_handlers) { {} }

    before do
      allow(Signal).to receive(:trap) do |signal, _handler = nil, &block|
        if block
          captured_signal_handlers[signal] = block
          'DEFAULT'
        end
      end
    end

    it 'starts scheduler in foreground and joins thread' do
      thread = instance_double(Thread, join: nil)
      allow(RailsCron).to receive(:start!).and_return(thread)

      expect { task('rails_cron:start').invoke }.to output(/started in foreground/).to_stdout
      expect(thread).to have_received(:join)
    end

    it 'aborts when scheduler is already running' do
      allow(RailsCron).to receive(:start!).and_return(nil)

      expect { task('rails_cron:start').invoke }
        .to raise_error(SystemExit)
        .and output(/rails_cron:start failed: scheduler is already running/).to_stderr
    end

    it 'handles interrupts by stopping scheduler' do
      thread = instance_double(Thread)
      allow(thread).to receive(:join).and_raise(Interrupt)
      allow(RailsCron).to receive(:start!).and_return(thread)
      allow(RailsCron).to receive(:stop!).with(timeout: 30).and_return(true)

      expect { task('rails_cron:start').invoke }.to output(/Received INT.*scheduler stopped/m).to_stdout
      expect(RailsCron).to have_received(:stop!).with(timeout: 30)
    end

    it 'handles TERM by stopping scheduler gracefully' do
      thread = instance_double(Thread)
      allow(RailsCron).to receive(:start!).and_return(thread)
      allow(RailsCron).to receive(:stop!).with(timeout: 30).and_return(true)

      allow(thread).to receive(:join) do
        captured_signal_handlers.fetch('TERM').call
      end

      expect { task('rails_cron:start').invoke }.to output(/Received TERM.*scheduler stopped/m).to_stdout
      expect(RailsCron).to have_received(:stop!).with(timeout: 30).once
    end

    it 'stops only once when multiple signals are received' do
      thread = instance_double(Thread)
      allow(RailsCron).to receive(:start!).and_return(thread)
      allow(RailsCron).to receive(:stop!).with(timeout: 30).and_return(true)

      allow(thread).to receive(:join) do
        captured_signal_handlers.fetch('TERM').call
        captured_signal_handlers.fetch('INT').call
      end

      expect { task('rails_cron:start').invoke }.to output(/Received TERM.*scheduler stopped/m).to_stdout

      expect(RailsCron).to have_received(:stop!).with(timeout: 30).once
    end

    it 'prints timeout message when scheduler stop times out' do
      thread = instance_double(Thread)
      allow(RailsCron).to receive(:start!).and_return(thread)
      allow(RailsCron).to receive(:stop!).with(timeout: 30).and_return(false)

      allow(thread).to receive(:join) do
        captured_signal_handlers.fetch('TERM').call
      end

      expect { task('rails_cron:start').invoke }.to output(/scheduler stop timed out/).to_stdout
    end

    it 'aborts when start raises unexpected errors' do
      allow(RailsCron).to receive(:start!).and_raise(StandardError, 'boom')

      expect { task('rails_cron:start').invoke }
        .to raise_error(SystemExit)
        .and output(/rails_cron:start failed: boom/).to_stderr
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
      signal_state = { shutdown_requested: false }
      allow(RailsCron).to receive(:stop!).and_raise(StandardError, 'stop blew up')

      expect do
        described_class.shutdown_scheduler(signal: 'TERM', signal_state: signal_state)
      end.to output(/Received TERM, stopping RailsCron scheduler/).to_stdout
                                                                  .and output(/shutdown failed: stop blew up/).to_stderr
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
