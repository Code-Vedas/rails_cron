# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::Definition::Registry do
  subject(:registry) { described_class.new }

  let(:concrete_registry) do
    Class.new(described_class) do
      def find_definition(_key)
        nil
      end
    end.new
  end

  describe 'abstract methods' do
    it 'raises for upsert_definition' do
      expect do
        registry.upsert_definition(key: 'job', cron: '* * * * *')
      end.to raise_error(NotImplementedError, /must implement #upsert_definition/)
    end

    it 'raises for remove_definition' do
      expect { registry.remove_definition('job') }.to raise_error(NotImplementedError, /must implement #remove_definition/)
    end

    it 'raises for find_definition' do
      expect { registry.find_definition('job') }.to raise_error(NotImplementedError, /must implement #find_definition/)
    end

    it 'raises for all_definitions' do
      expect { registry.all_definitions }.to raise_error(NotImplementedError, /must implement #all_definitions/)
    end
  end

  describe '#enable_definition/#disable_definition' do
    it 'returns nil when enabling a missing definition' do
      expect(concrete_registry.enable_definition('missing')).to be_nil
    end

    it 'returns nil when disabling a missing definition' do
      expect(concrete_registry.disable_definition('missing')).to be_nil
    end
  end
end
