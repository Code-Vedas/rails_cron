# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsCron::CronDefinition, type: :model do
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
end
