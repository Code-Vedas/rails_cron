# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes
RSpec.describe RailsCron::Lock::Adapter do
  describe '#acquire' do
    it 'raises NotImplementedError when called directly on base class' do
      adapter = described_class.new

      expect { adapter.acquire('test-key', 60) }.to raise_error(NotImplementedError, /must implement #acquire/)
    end
  end

  describe '#release' do
    it 'raises NotImplementedError when called directly on base class' do
      adapter = described_class.new

      expect { adapter.release('test-key') }.to raise_error(NotImplementedError, /must implement #release/)
    end
  end
end

RSpec.describe RailsCron::Lock::NullAdapter do
  let(:adapter) { described_class.new }

  describe '#acquire' do
    it 'always returns true' do
      expect(adapter.acquire('test-key', 60)).to be(true)
    end

    it 'returns true regardless of key' do
      expect(adapter.acquire('any-key', 30)).to be(true)
      expect(adapter.acquire('another-key', 90)).to be(true)
    end
  end

  describe '#release' do
    it 'always returns true' do
      expect(adapter.release('test-key')).to be(true)
    end

    it 'returns true regardless of key' do
      expect(adapter.release('any-key')).to be(true)
      expect(adapter.release('another-key')).to be(true)
    end
  end
end
# rubocop:enable RSpec/MultipleDescribes
