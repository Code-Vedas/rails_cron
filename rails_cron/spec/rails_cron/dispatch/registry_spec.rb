# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Dispatch::Registry do
  describe '#log_dispatch' do
    it 'raises NotImplementedError' do
      registry = described_class.new

      expect do
        registry.log_dispatch('key', Time.current, 'node-1')
      end.to raise_error(NotImplementedError, /must implement #log_dispatch/)
    end
  end

  describe '#find_dispatch' do
    it 'raises NotImplementedError' do
      registry = described_class.new

      expect do
        registry.find_dispatch('key', Time.current)
      end.to raise_error(NotImplementedError, /must implement #find_dispatch/)
    end
  end

  describe '#dispatched?' do
    subject(:registry) { TestRegistry.new }

    let(:test_registry_class) do
      Class.new(described_class) do
        def log_dispatch(key, fire_time, node_id, status = 'dispatched')
          @log = { key: key, fire_time: fire_time, node_id: node_id, status: status }
        end

        def find_dispatch(key, fire_time)
          return nil unless @log

          @log if @log[:key] == key && @log[:fire_time] == fire_time
        end
      end
    end

    before { stub_const('TestRegistry', test_registry_class) }

    it 'returns true when dispatch exists' do
      fire_time = Time.current
      registry.log_dispatch('key', fire_time, 'node-1')

      expect(registry.dispatched?('key', fire_time)).to be true
    end

    it 'returns false when dispatch does not exist' do
      expect(registry.dispatched?('key', Time.current)).to be false
    end
  end
end
