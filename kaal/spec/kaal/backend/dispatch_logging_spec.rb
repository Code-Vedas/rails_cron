# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::Backend::DispatchLogging do
  # Test class that includes the DispatchLogging module
  let(:test_class_with_registry) do
    Class.new do
      include Kaal::Backend::DispatchLogging

      attr_accessor :registry

      def dispatch_registry
        @dispatch_registry ||= instance_double(Kaal::Dispatch::MemoryEngine)
      end
    end
  end

  # Test class WITHOUT dispatch_registry method
  let(:test_class_without_registry) do
    Class.new do
      include Kaal::Backend::DispatchLogging
    end
  end

  describe '#log_dispatch_attempt' do
    around do |example|
      original_logger = Kaal.configuration.logger
      original_logging = Kaal.configuration.enable_log_dispatch_registry

      example.run
    ensure
      Kaal.configuration.logger = original_logger
      Kaal.configuration.enable_log_dispatch_registry = original_logging
    end

    context 'when adapter does not respond to dispatch_registry' do
      it 'returns early without logging' do
        adapter = test_class_without_registry.new
        logger = instance_double(Logger, error: nil)
        Kaal.configuration.logger = logger
        Kaal.configuration.enable_log_dispatch_registry = true

        # Should not raise error despite missing dispatch_registry method
        expect { adapter.log_dispatch_attempt('railscron:dispatch:job:1234567890') }.not_to raise_error
        expect(logger).not_to have_received(:error)
      end
    end

    context 'when logging fails and logger is nil' do
      it 'handles error silently without logger' do
        adapter = test_class_with_registry.new
        registry = instance_double(Kaal::Dispatch::MemoryEngine)
        allow(adapter).to receive(:dispatch_registry).and_return(registry)
        allow(registry).to receive(:log_dispatch).and_raise(StandardError, 'Test error')

        # Ensure logger is nil
        Kaal.configuration.logger = nil
        Kaal.configuration.enable_log_dispatch_registry = true

        # Should not raise, even though logger is nil
        expect { adapter.log_dispatch_attempt('railscron:dispatch:job:1234567890') }.not_to raise_error
      end
    end

    context 'when dispatch registry is nil' do
      it 'returns without attempting to log' do
        adapter = test_class_with_registry.new
        allow(adapter).to receive(:dispatch_registry).and_return(nil)
        Kaal.configuration.enable_log_dispatch_registry = true

        expect { adapter.log_dispatch_attempt('railscron:dispatch:job:1234567890') }.not_to raise_error
      end
    end

    context 'when logging succeeds' do
      it 'parses lock key and calls dispatch_registry' do
        adapter = test_class_with_registry.new
        registry = instance_double(Kaal::Dispatch::MemoryEngine)
        allow(adapter).to receive(:dispatch_registry).and_return(registry)
        allow(registry).to receive(:log_dispatch)

        Kaal.configuration.enable_log_dispatch_registry = true

        adapter.log_dispatch_attempt('railscron:dispatch:daily_job:1609459200')

        expect(registry).to have_received(:log_dispatch).with(
          'daily_job',
          Time.at(1_609_459_200),
          anything, # node_id (hostname)
          'dispatched'
        )
      end
    end
  end

  describe '.parse_lock_key' do
    it 'parses a standard lock key correctly' do
      cron_key, fire_time = described_class.parse_lock_key('railscron:dispatch:daily_report:1609459200')

      expect(cron_key).to eq('daily_report')
      expect(fire_time).to eq(Time.at(1_609_459_200))
    end

    it 'handles cron keys with colons' do
      cron_key, fire_time = described_class.parse_lock_key('myapp:dispatch:jobs:daily:report:1609459200')

      expect(cron_key).to eq('jobs:daily:report')
      expect(fire_time).to eq(Time.at(1_609_459_200))
    end

    it 'handles simple cron keys' do
      cron_key, fire_time = described_class.parse_lock_key('app:dispatch:job:1234567890')

      expect(cron_key).to eq('job')
      expect(fire_time).to eq(Time.at(1_234_567_890))
    end
  end

  describe '#parse_lock_key' do
    it 'delegates to the shared parser as an instance method' do
      adapter = test_class_with_registry.new

      cron_key, fire_time = adapter.parse_lock_key('railscron:dispatch:daily_report:1609459200')

      expect(cron_key).to eq('daily_report')
      expect(fire_time).to eq(Time.at(1_609_459_200))
    end
  end
end
