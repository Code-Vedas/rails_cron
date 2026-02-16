# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails_helper'

RSpec.describe RailsCron::CronDispatch, type: :model do
  describe 'table' do
    it 'uses custom table name' do
      expect(described_class.table_name).to eq('rails_cron_dispatches')
    end
  end

  describe 'validations' do
    subject { described_class.new }

    it { is_expected.to validate_presence_of(:key) }
    it { is_expected.to validate_presence_of(:fire_time) }
    it { is_expected.to validate_presence_of(:dispatched_at) }
    it { is_expected.to validate_presence_of(:node_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[dispatched failed]) }
  end

  describe '#create' do
    it 'creates a valid record with all required attributes' do
      fire_time = Time.current
      dispatched_at = Time.current

      record = described_class.create!(
        key: 'send_emails',
        fire_time: fire_time,
        dispatched_at: dispatched_at,
        node_id: 'worker-1',
        status: 'dispatched'
      )

      expect(record).to be_persisted
      expect(record.key).to eq('send_emails')
      expect(record.fire_time).to be_within(1.second).of(fire_time)
      expect(record.dispatched_at).to be_within(1.second).of(dispatched_at)
      expect(record.node_id).to eq('worker-1')
      expect(record.status).to eq('dispatched')
    end

    it 'enforces presence validations' do
      expect do
        described_class.create!(key: 'job1')
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'enforces status inclusion' do
      expect do
        described_class.create!(
          key: 'job1',
          fire_time: Time.current,
          dispatched_at: Time.current,
          node_id: 'worker-1',
          status: 'invalid_status'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'accepts valid status values' do
      %w[dispatched failed].each do |status|
        record = described_class.create!(
          key: 'job1',
          fire_time: Time.current,
          dispatched_at: Time.current,
          node_id: 'worker-1',
          status: status
        )
        expect(record.status).to eq(status)
      end
    end
  end

  describe 'scopes' do
    let!(:recent_record) { create_cron_dispatch(key: 'job1', dispatched_at: 1.minute.ago) }
    let!(:old_record) { create_cron_dispatch(key: 'job2', dispatched_at: 30.minutes.ago) }
    let!(:failed_record) { create_cron_dispatch(key: 'job3', status: 'failed', dispatched_at: 5.minutes.ago) }

    describe '.recent' do
      it 'returns records ordered by dispatched_at descending' do
        records = described_class.recent
        expect(records).to contain_exactly(recent_record, failed_record, old_record)
      end

      it 'limits results by default' do
        records = described_class.recent
        expect(records.count).to be <= 100
      end

      it 'accepts custom limit' do
        records = described_class.recent(1)
        expect(records.count).to eq(1)
      end
    end

    describe '.by_key' do
      it 'filters records by key' do
        records = described_class.by_key('job1')
        expect(records.map(&:key).uniq).to eq(['job1'])
      end

      it 'returns empty when key does not exist' do
        records = described_class.by_key('non-existent')
        expect(records).to be_empty
      end
    end

    describe '.by_node' do
      before do
        create_cron_dispatch(key: 'j1', node_id: 'worker-1')
        create_cron_dispatch(key: 'j2', node_id: 'worker-2')
      end

      it 'filters records by node_id' do
        records = described_class.by_node('worker-1')
        expect(records.map(&:node_id).uniq).to eq(['worker-1'])
      end
    end

    describe '.by_status' do
      it 'filters records by status' do
        records = described_class.by_status('failed')
        expect(records.map(&:status).uniq).to eq(['failed'])
      end

      it 'returns empty when status does not exist' do
        records = described_class.by_status('unknown')
        expect(records).to be_empty
      end
    end

    describe '.since' do
      it 'returns records dispatched after given timestamp' do
        timestamp = 10.minutes.ago
        records = described_class.since(timestamp)
        expect(records).to include(recent_record, failed_record)
        expect(records).not_to include(old_record)
      end
    end
  end

  describe 'timestamps' do
    it 'automatically sets created_at and updated_at' do
      record = described_class.create!(
        key: 'job1',
        fire_time: Time.current,
        dispatched_at: Time.current,
        node_id: 'worker-1',
        status: 'dispatched'
      )

      expect(record.created_at).to be_present
      expect(record.updated_at).to be_present
    end
  end

  describe 'composite unique index' do
    it 'enforces unique constraint on (key, fire_time)' do
      fire_time = Time.current
      described_class.create!(
        key: 'job1',
        fire_time: fire_time,
        dispatched_at: Time.current,
        node_id: 'worker-1',
        status: 'dispatched'
      )

      expect do
        described_class.create!(
          key: 'job1',
          fire_time: fire_time,
          dispatched_at: Time.current,
          node_id: 'worker-2',
          status: 'dispatched'
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows same key with different fire_time' do
      now = Time.current
      described_class.create!(
        key: 'job1',
        fire_time: now,
        dispatched_at: Time.current,
        node_id: 'worker-1',
        status: 'dispatched'
      )

      later = now + 1.hour
      expect do
        described_class.create!(
          key: 'job1',
          fire_time: later,
          dispatched_at: Time.current,
          node_id: 'worker-1',
          status: 'dispatched'
        )
      end.not_to raise_error
    end
  end

  private

  def create_cron_dispatch(key:, fire_time: Time.current, dispatched_at: Time.current, node_id: 'worker-1', status: 'dispatched')
    described_class.create!(
      key: key,
      fire_time: fire_time,
      dispatched_at: dispatched_at,
      node_id: node_id,
      status: status
    )
  end
end
