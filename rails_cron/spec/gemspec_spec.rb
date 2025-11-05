# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'rails_cron.gemspec' do # rubocop:disable RSpec/DescribeClass
  subject(:spec) { Gem::Specification.load('rails_cron.gemspec') }

  it 'has rails_cron name' do
    expect(spec.name).to eq('rails_cron')
  end

  it 'has rails_cron version' do
    expect(spec.version).to eq(RailsCron::VERSION)
  end
end
