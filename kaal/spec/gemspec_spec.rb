# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'kaal.gemspec' do # rubocop:disable RSpec/DescribeClass
  subject(:spec) { Gem::Specification.load('kaal.gemspec') }

  it 'has kaal name' do
    expect(spec.name).to eq('kaal')
  end

  it 'has kaal version' do
    expect(spec.version).to eq(Kaal::VERSION)
  end
end
