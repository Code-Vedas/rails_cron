# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'stringio'

RSpec.describe RailsCron::Railtie do
  before do
    RailsCron.reset_configuration!
  end

  describe '.ensure_logger!' do
    it 'sets configuration logger when Rails.logger is present' do
      test_logger = Logger.new(StringIO.new)
      allow(Rails).to receive(:logger).and_return(test_logger)

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be(test_logger)
    end

    it 'does not override an existing configuration logger' do
      existing_logger = Logger.new(StringIO.new)
      RailsCron.configuration.logger = existing_logger

      allow(Rails).to receive(:logger).and_return(Logger.new(StringIO.new))

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be(existing_logger)
    end

    it 'does nothing when Rails.logger is nil' do
      allow(Rails).to receive(:logger).and_return(nil)

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be_nil
    end

    it 'does nothing when Rails.logger raises NoMethodError' do
      allow(Rails).to receive(:logger).and_raise(NoMethodError)

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be_nil

      # Restore original Rails.logger before after hooks run
      # to prevent interference with RSpec-Rails cleanup
      allow(Rails).to receive(:logger).and_call_original
    end
  end

  describe '.register_signal_handlers' do
    let(:test_logger) { instance_spy(Logger) }

    before do
      allow(RailsCron).to receive(:logger).and_return(test_logger)
    end

    it 'registers signal handlers for TERM and INT signals' do
      expecting_traps = []
      allow(Signal).to receive(:trap) do |signal, _handler = nil, &block|
        expecting_traps << signal if signal.is_a?(String)
        # Simulate the trap block being called
        block&.call
        nil
      end
      allow(RailsCron).to receive(:stop!)

      described_class.register_signal_handlers

      expect(expecting_traps).to include('TERM', 'INT')
    end

    it 'calls RailsCron.stop! with timeout 30 when signal is received' do
      signal_blocks = []
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        signal_blocks << block if block
        nil
      end

      called_with = []
      allow(RailsCron).to receive(:stop!) do |kwargs|
        called_with << kwargs
      end

      described_class.register_signal_handlers

      # Call the last block to simulate signal (the one with our handler)
      signal_blocks.last&.call if signal_blocks.any?

      expect(called_with).to include(timeout: 30)
    end

    it 'logs the signal when logger is available' do
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        block&.call
        nil
      end
      allow(RailsCron).to receive(:stop!).and_return(true)

      described_class.register_signal_handlers

      # Called once for TERM and once for INT
      expect(test_logger).to have_received(:info).with(/Received.*signal/).at_least(:once)
      expect(test_logger).not_to have_received(:warn)
    end

    it 'handles StandardError when registering signals' do
      allow(Signal).to receive(:trap).and_raise(StandardError, 'Trap error')

      described_class.register_signal_handlers

      expect(test_logger).to have_received(:warn).with(/Failed to register signal handlers/)
    end

    it 'handles StandardError when registering signals with nil logger' do
      allow(RailsCron).to receive(:logger).and_return(nil)
      allow(Signal).to receive(:trap).and_raise(StandardError, 'Trap error')

      expect { described_class.register_signal_handlers }.not_to raise_error
    end

    it 'handles signal trapping when logger is nil' do
      allow(RailsCron).to receive(:logger).and_return(nil)
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        block&.call
        nil
      end
      allow(RailsCron).to receive(:stop!)

      expect { described_class.register_signal_handlers }.not_to raise_error
    end

    it 'does not call logger.info when logger is nil' do
      allow(RailsCron).to receive(:logger).and_return(nil)
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        block&.call
        nil
      end
      allow(RailsCron).to receive(:stop!)

      described_class.register_signal_handlers

      expect(test_logger).not_to have_received(:info)
    end

    it 'rescues exceptions from stop! call in signal handler and logs them' do
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        block&.call
        nil
      end
      allow(RailsCron).to receive(:stop!).and_raise(StandardError, 'Stop error')

      expect { described_class.register_signal_handlers }.not_to raise_error

      expect(test_logger).to have_received(:error).with(/Error stopping scheduler.*Stop error/).at_least(:once)
    end

    it 'rescues exceptions from stop! when logger is nil' do
      allow(RailsCron).to receive(:logger).and_return(nil)
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        block&.call
        nil
      end
      allow(RailsCron).to receive(:stop!).and_raise(StandardError, 'Stop error')

      expect { described_class.register_signal_handlers }.not_to raise_error
    end

    it 'logs warning when stop times out with logger present' do
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        block&.call
        nil
      end
      allow(RailsCron).to receive(:stop!).and_return(false)

      described_class.register_signal_handlers

      expect(test_logger).to have_received(:warn).with(/did not stop within timeout/).at_least(:once)
    end

    it 'does not crash when stop times out with nil logger' do
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        block&.call
        nil
      end
      allow(RailsCron).to receive_messages(logger: nil, stop!: false)

      expect { described_class.register_signal_handlers }.not_to raise_error
    end

    it 'chains previous callable signal handlers' do
      previous_handler_called = []
      previous_handler = proc { previous_handler_called << true }

      trap_count = 0
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        trap_count += 1
        case trap_count
        when 1 # First call to get the old handler (with 'IGNORE')
          previous_handler
        when 2 # Second call to restore old handler
          nil
        when 3 # Third call to install our new handler
          block&.call
          nil
        end
      end
      allow(RailsCron).to receive(:stop!).and_return(true)

      described_class.register_signal_handlers

      expect(previous_handler_called).not_to be_empty
    end

    it 'logs debug message for string command handlers' do
      trap_count = 0
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        trap_count += 1
        case trap_count
        when 1 # First call returns string command
          'some_command'
        when 2 # Second call to restore
          nil
        when 3 # Third call to install our handler
          block&.call
          nil
        end
      end
      allow(RailsCron).to receive(:stop!).and_return(true)

      described_class.register_signal_handlers

      expect(test_logger).to have_received(:debug).with(/Previous.*handler was a command/).at_least(:once)
    end

    it 'does not call DEFAULT or IGNORE handlers' do
      trap_count = 0
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        trap_count += 1
        case trap_count
        when 1, 4 # First call for each signal returns DEFAULT
          'DEFAULT'
        when 2, 5 # Second call to restore
          nil
        when 3, 6 # Third call to install our handler
          block&.call
          nil
        end
      end
      allow(RailsCron).to receive(:stop!).and_return(true)

      described_class.register_signal_handlers

      expect(test_logger).not_to have_received(:debug).with(/Previous.*handler was a command/)
    end

    it 'handles nil previous handler gracefully' do
      trap_count = 0
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        trap_count += 1
        case trap_count
        when 1, 3 # First call for each signal returns nil
        when 2, 4 # Second call to install our handler (restore skipped for nil)
          block&.call
        end
        nil
      end
      allow(RailsCron).to receive(:stop!).and_return(true)

      expect { described_class.register_signal_handlers }.not_to raise_error
    end

    it 'handles IGNORE previous handler without logging' do
      trap_count = 0
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        trap_count += 1
        case trap_count
        when 1, 3 # First call for each signal returns IGNORE
          'IGNORE'
        when 2, 4 # Second call to install our handler (restore skipped for IGNORE)
          block&.call
          nil
        end
      end
      allow(RailsCron).to receive(:stop!).and_return(true)

      described_class.register_signal_handlers

      expect(test_logger).not_to have_received(:debug)
    end

    it 'handles non-callable non-string previous handler gracefully' do
      trap_count = 0
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        trap_count += 1
        case trap_count
        when 1, 4 # First call for each signal returns a symbol (non-callable, non-string)
          :some_symbol
        when 2, 5 # Second call to restore
          nil
        when 3, 6 # Third call to install our handler
          block&.call
          nil
        end
      end
      allow(RailsCron).to receive(:stop!).and_return(true)

      expect { described_class.register_signal_handlers }.not_to raise_error
      expect(test_logger).not_to have_received(:debug)
    end

    it 'handles string command handler when logger is nil' do
      trap_count = 0
      allow(Signal).to receive(:trap) do |_signal, _handler = nil, &block|
        trap_count += 1
        case trap_count
        when 1, 4 # First call for each signal returns string command
          'some_command'
        when 2, 5 # Second call to restore
          nil
        when 3, 6 # Third call to install our handler
          block&.call
          nil
        end
      end
      allow(RailsCron).to receive_messages(logger: nil, stop!: true)

      expect { described_class.register_signal_handlers }.not_to raise_error
    end
  end

  describe 'Railtie class' do
    it 'is a Rails Railtie' do
      expect(described_class).to be < Rails::Railtie
    end

    it 'responds to ensure_logger!' do
      expect(described_class).to respond_to(:ensure_logger!)
    end

    it 'responds to register_signal_handlers' do
      expect(described_class).to respond_to(:register_signal_handlers)
    end
  end

  describe '.handle_shutdown' do
    it 'stops scheduler when running' do
      test_logger = instance_spy(Logger)
      allow(RailsCron).to receive_messages(running?: true, logger: test_logger)
      allow(RailsCron).to receive(:stop!).and_return(true)

      described_class.handle_shutdown

      expect(test_logger).to have_received(:info).with(/Rails is shutting down/)
      expect(RailsCron).to have_received(:stop!).with(timeout: 10)
      expect(test_logger).not_to have_received(:warn)
    end

    it 'does nothing when not running' do
      allow(RailsCron).to receive_messages(running?: false, logger: instance_spy(Logger))
      allow(RailsCron).to receive(:stop!)

      described_class.handle_shutdown

      expect(RailsCron).not_to have_received(:stop!)
    end

    it 'does not crash when logger is nil' do
      allow(RailsCron).to receive_messages(running?: true, logger: nil)
      allow(RailsCron).to receive(:stop!).and_return(true)

      expect { described_class.handle_shutdown }.not_to raise_error
      expect(RailsCron).to have_received(:stop!).with(timeout: 10)
    end

    it 'logs warning when stop times out with logger present' do
      test_logger = instance_spy(Logger)
      allow(RailsCron).to receive_messages(running?: true, logger: test_logger)
      allow(RailsCron).to receive(:stop!).and_return(false)

      described_class.handle_shutdown

      expect(test_logger).to have_received(:warn).with(/did not stop within timeout/)
    end

    it 'does not crash when stop times out with nil logger' do
      allow(RailsCron).to receive_messages(running?: true, logger: nil)
      allow(RailsCron).to receive(:stop!).and_return(false)

      expect { described_class.handle_shutdown }.not_to raise_error
    end

    it 'rescues exceptions from stop! in shutdown and logs them' do
      test_logger = instance_spy(Logger)
      allow(RailsCron).to receive_messages(running?: true, logger: test_logger)
      allow(RailsCron).to receive(:stop!).and_raise(StandardError, 'Shutdown error')

      expect { described_class.handle_shutdown }.not_to raise_error

      expect(test_logger).to have_received(:error).with(/Error stopping scheduler.*Shutdown error/)
    end

    it 'rescues exceptions from stop! in shutdown when logger is nil' do
      allow(RailsCron).to receive_messages(running?: true, logger: nil)
      allow(RailsCron).to receive(:stop!).and_raise(StandardError, 'Shutdown error')

      expect { described_class.handle_shutdown }.not_to raise_error
    end
  end
end
