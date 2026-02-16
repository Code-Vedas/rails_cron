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
    end
  end

  describe '.register_signal_handlers' do
    let(:test_logger) { instance_spy(Logger) }

    before do
      allow(RailsCron).to receive(:logger).and_return(test_logger)
    end

    it 'registers signal handlers for TERM and INT signals' do
      expecting_traps = []
      allow(Signal).to receive(:trap) do |signal, &block|
        expecting_traps << signal
        # Simulate the trap block being called
        block&.call
      end
      allow(RailsCron).to receive(:stop!)

      described_class.register_signal_handlers

      expect(expecting_traps).to include('TERM', 'INT')
    end

    it 'calls RailsCron.stop! with timeout 30 when signal is received' do
      signal_block = nil
      allow(Signal).to receive(:trap) do |_signal, &block|
        signal_block = block
      end

      called_with = []
      allow(RailsCron).to receive(:stop!) do |kwargs|
        called_with << kwargs
      end

      described_class.register_signal_handlers

      # Call the block to simulate signal
      signal_block&.call

      expect(called_with).to include(timeout: 30)
    end

    it 'logs the signal when logger is available' do
      allow(Signal).to receive(:trap) do |_signal, &block|
        block&.call
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
      allow(Signal).to receive(:trap) do |_signal, &block|
        block&.call
      end
      allow(RailsCron).to receive(:stop!)

      expect { described_class.register_signal_handlers }.not_to raise_error
    end

    it 'does not call logger.info when logger is nil' do
      allow(RailsCron).to receive(:logger).and_return(nil)
      allow(Signal).to receive(:trap) do |_signal, &block|
        block&.call
      end
      allow(RailsCron).to receive(:stop!)

      described_class.register_signal_handlers

      expect(test_logger).not_to have_received(:info)
    end

    it 'rescues exceptions from stop! call in signal handler and logs them' do
      allow(Signal).to receive(:trap) do |_signal, &block|
        block&.call
      end
      allow(RailsCron).to receive(:stop!).and_raise(StandardError, 'Stop error')

      expect { described_class.register_signal_handlers }.not_to raise_error

      expect(test_logger).to have_received(:error).with(/Error stopping scheduler.*Stop error/).at_least(:once)
    end

    it 'rescues exceptions from stop! when logger is nil' do
      allow(RailsCron).to receive(:logger).and_return(nil)
      allow(Signal).to receive(:trap) do |_signal, &block|
        block&.call
      end
      allow(RailsCron).to receive(:stop!).and_raise(StandardError, 'Stop error')

      expect { described_class.register_signal_handlers }.not_to raise_error
    end

    it 'logs warning when stop times out with logger present' do
      allow(Signal).to receive(:trap) do |_signal, &block|
        block&.call
      end
      allow(RailsCron).to receive(:stop!).and_return(false)

      described_class.register_signal_handlers

      expect(test_logger).to have_received(:warn).with(/did not stop within timeout/).at_least(:once)
    end

    it 'does not crash when stop times out with nil logger' do
      allow(Signal).to receive(:trap) do |_signal, &block|
        block&.call
      end
      allow(RailsCron).to receive_messages(logger: nil, stop!: false)

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
