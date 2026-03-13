# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'fakeredis'

RSpec.describe Kaal::Definition::RedisEngine do
  subject(:engine) { described_class.new(redis, namespace: 'kaal') }

  let(:redis) { FakeRedis::Redis.new }

  before { redis.flushdb }

  it 'upserts and finds a definition' do
    result = engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', enabled: true, source: 'code', metadata: { team: 'ops' })

    expect(result[:key]).to eq('job:daily')
    found = engine.find_definition('job:daily')
    expect(found[:cron]).to eq('0 9 * * *')
    expect(found[:enabled]).to be(true)
    expect(found[:metadata]).to eq({ 'team' => 'ops' })
    expect(found[:created_at]).to be_a(Time)
    expect(found[:updated_at]).to be_a(Time)
    expect(found[:disabled_at]).to be_nil
  end

  it 'preserves created_at on update and sets disabled_at when disabled' do
    created = engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', enabled: true, source: 'code')[:created_at]

    sleep(0.01)
    updated = engine.upsert_definition(key: 'job:daily', cron: '0 10 * * *', enabled: false, source: 'api')

    expect(updated[:created_at].to_i).to eq(created.to_i)
    expect(updated[:updated_at]).to be > created
    expect(updated[:disabled_at]).to be_a(Time)
  end

  it 'removes definitions and returns removed payload' do
    engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *')

    removed = engine.remove_definition('job:daily')

    expect(removed[:key]).to eq('job:daily')
    expect(engine.find_definition('job:daily')).to be_nil
  end

  it 'returns nil when removing or finding missing definitions' do
    expect(engine.remove_definition('missing')).to be_nil
    expect(engine.find_definition('missing')).to be_nil
  end

  it 'returns all definitions and filters invalid JSON entries' do
    engine.upsert_definition(key: 'job:one', cron: '0 9 * * *')
    redis.hset('kaal:definitions', 'bad:json', '{not-json')

    keys = engine.all_definitions.map { |definition| definition[:key] }
    expect(keys).to contain_exactly('job:one')
  end

  it 'handles invalid timestamps by returning nil for parsed times' do
    redis.hset(
      'kaal:definitions',
      'job:bad-time',
      {
        key: 'job:bad-time',
        cron: '* * * * *',
        enabled: true,
        source: 'code',
        metadata: {},
        created_at: 'not-a-time',
        updated_at: 'also-not-a-time',
        disabled_at: 'still-not-a-time'
      }.to_json
    )

    found = engine.find_definition('job:bad-time')

    expect(found[:created_at]).to be_nil
    expect(found[:updated_at]).to be_nil
    expect(found[:disabled_at]).to be_nil
  end

  it 'casts non-true enabled values to false' do
    redis.hset(
      'kaal:definitions',
      'job:disabled',
      {
        key: 'job:disabled',
        cron: '* * * * *',
        enabled: 'true',
        source: 'code',
        metadata: {}
      }.to_json
    )

    expect(engine.find_definition('job:disabled')[:enabled]).to be(false)
  end
end
