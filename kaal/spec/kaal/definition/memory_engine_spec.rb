# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Definition::MemoryEngine do
  subject(:engine) { described_class.new }

  describe '#upsert_definition' do
    it 'creates a new definition' do
      result = engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', source: 'code')

      expect(result[:key]).to eq('job:daily')
      expect(result[:cron]).to eq('0 9 * * *')
      expect(result[:enabled]).to be(true)
      expect(result[:source]).to eq('code')
    end

    it 'updates an existing definition' do
      engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', source: 'code')

      result = engine.upsert_definition(key: 'job:daily', cron: '0 10 * * *', enabled: false, source: 'api')

      expect(result[:cron]).to eq('0 10 * * *')
      expect(result[:enabled]).to be(false)
      expect(result[:source]).to eq('api')
      expect(result[:disabled_at]).to be_a(Time)
    end

    it 'returns a defensive copy of the stored definition' do
      result = engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', metadata: { team: 'ops' })

      result[:cron] = '0 10 * * *'
      result[:metadata][:team] = 'platform'

      stored_definition = engine.find_definition('job:daily')
      expect(stored_definition[:cron]).to eq('0 9 * * *')
      expect(stored_definition[:metadata]).to eq(team: 'ops')
    end

    it 'stores a defensive copy of the input metadata' do
      metadata = { team: 'ops', tags: ['daily'] }

      engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', metadata:)
      metadata[:team] = 'platform'
      metadata[:tags] << 'critical'

      stored_definition = engine.find_definition('job:daily')
      expect(stored_definition[:metadata]).to eq(team: 'ops', tags: ['daily'])
    end

    it 'preserves disabled_at when re-upserting an already-disabled definition' do
      first_time = Time.current.change(usec: 0)
      second_time = first_time + 1.second
      allow(Time).to receive(:current).and_return(first_time, second_time)

      first_result = engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', enabled: false)
      second_result = engine.upsert_definition(key: 'job:daily', cron: '0 10 * * *', enabled: false)

      expect(second_result[:disabled_at]).to eq(first_result[:disabled_at])
    end
  end

  it 'finds and removes definitions' do
    engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *')

    expect(engine.find_definition('job:daily')).not_to be_nil
    expect(engine.remove_definition('job:daily')[:key]).to eq('job:daily')
    expect(engine.find_definition('job:daily')).to be_nil
  end

  it 'returns only enabled definitions' do
    engine.upsert_definition(key: 'job:enabled', cron: '0 9 * * *', enabled: true)
    engine.upsert_definition(key: 'job:disabled', cron: '0 10 * * *', enabled: false)

    expect(engine.enabled_definitions.map { |d| d[:key] }).to eq(['job:enabled'])
  end

  it 'supports enable/disable lifecycle' do
    engine.upsert_definition(key: 'job:daily', cron: '0 9 * * *', enabled: true)

    engine.disable_definition('job:daily')
    expect(engine.find_definition('job:daily')[:enabled]).to be(false)

    engine.enable_definition('job:daily')
    expect(engine.find_definition('job:daily')[:enabled]).to be(true)
  end
end
