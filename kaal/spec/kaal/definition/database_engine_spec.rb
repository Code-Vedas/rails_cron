# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails_helper'

RSpec.describe Kaal::Definition::DatabaseEngine do
  subject(:engine) { described_class.new }

  before do
    Kaal::CronDefinition.delete_all
  end

  it 'upserts and queries definitions' do
    engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', source: 'code')

    found = engine.find_definition('job:daily')
    expect(found[:key]).to eq('job:daily')
    expect(found[:enabled]).to be(true)
  end

  it 'returns enabled definitions only' do
    engine.upsert_definition(key: 'job:enabled', cron: '0 9 * * *', enabled: true)
    engine.upsert_definition(key: 'job:disabled', cron: '0 10 * * *', enabled: false)

    expect(engine.enabled_definitions.map { |d| d[:key] }).to eq(['job:enabled'])
  end

  it 'returns all definitions' do
    engine.upsert_definition(key: 'job:one', cron: '0 9 * * *', enabled: true)
    engine.upsert_definition(key: 'job:two', cron: '0 10 * * *', enabled: false)

    expect(engine.all_definitions.map { |d| d[:key] }).to eq(%w[job:one job:two])
  end

  it 'supports remove_definition' do
    engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *')

    removed = engine.remove_definition('job:daily')
    expect(removed[:key]).to eq('job:daily')
    expect(engine.find_definition('job:daily')).to be_nil
  end

  it 'returns nil when removing a missing definition' do
    expect(engine.remove_definition('missing')).to be_nil
  end
end
