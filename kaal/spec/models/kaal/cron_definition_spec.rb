# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kaal::CronDefinition, type: :model do
  subject(:record) do
    described_class.new(
      key: 'job:daily',
      cron: '0 9 * * *',
      enabled: true,
      source: 'code',
      metadata: {}
    )
  end

  it { is_expected.to validate_presence_of(:key) }
  it { is_expected.to validate_presence_of(:cron) }
  it { is_expected.to validate_presence_of(:source) }
  it { is_expected.to validate_uniqueness_of(:key) }

  it 'supports enabled/disabled scopes' do
    described_class.delete_all
    described_class.create!(key: 'job:enabled', cron: '0 9 * * *', enabled: true, source: 'code', metadata: {})
    described_class.create!(key: 'job:disabled', cron: '0 10 * * *', enabled: false, source: 'code', metadata: {})

    expect(described_class.enabled.pluck(:key)).to eq(['job:enabled'])
    expect(described_class.disabled.pluck(:key)).to eq(['job:disabled'])
  end

  describe '.upsert_definition!' do
    it 'retries with the persisted record when a unique constraint race occurs' do
      new_record = instance_double(described_class)
      existing_record = instance_double(described_class)

      allow(described_class).to receive(:find_or_initialize_by).with(key: 'job:daily').and_return(new_record)
      allow(described_class).to receive(:find_by!).with(key: 'job:daily').and_return(existing_record)
      allow(new_record).to receive(:assign_attributes)
      allow(new_record).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new('duplicate key'))
      allow(existing_record).to receive(:assign_attributes)
      allow(existing_record).to receive(:save!).and_return(true)

      result = described_class.upsert_definition!(
        key: 'job:daily',
        cron: '0 9 * * *',
        enabled: true,
        source: 'code',
        metadata: { team: 'ops' }
      )

      expect(result).to be(existing_record)
      expect(existing_record).to have_received(:assign_attributes).with(
        hash_including(
          cron: '0 9 * * *',
          enabled: true,
          source: 'code',
          metadata: { team: 'ops' },
          disabled_at: nil
        )
      )
      expect(existing_record).to have_received(:save!)
    end

    it 'preserves disabled_at when re-upserting an already-disabled definition' do
      disabled_at = 2.days.ago.change(usec: 0)
      described_class.create!(
        key: 'job:disabled',
        cron: '0 9 * * *',
        enabled: false,
        source: 'code',
        metadata: {},
        disabled_at:
      )

      result = described_class.upsert_definition!(
        key: 'job:disabled',
        cron: '0 10 * * *',
        enabled: false,
        source: 'api',
        metadata: { team: 'ops' }
      )

      expect(result.reload.disabled_at.change(usec: 0)).to eq(disabled_at)
    end
  end
end
