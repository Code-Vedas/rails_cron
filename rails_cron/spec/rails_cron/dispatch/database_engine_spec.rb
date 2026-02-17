# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Dispatch::DatabaseEngine do
  subject(:engine) { described_class.new }

  let(:cron_dispatch_class) { class_double(RailsCron::CronDispatch) }

  before do
    stub_const('RailsCron::CronDispatch', cron_dispatch_class)
  end

  describe '#log_dispatch' do
    it 'creates dispatch record in database' do
      fire_time = Time.current
      dispatch_record = instance_double(RailsCron::CronDispatch)
      allow(cron_dispatch_class).to receive(:create!).and_return(dispatch_record)

      result = engine.log_dispatch('daily_report', fire_time, 'node-1')

      expect(cron_dispatch_class).to have_received(:create!).with(
        key: 'daily_report',
        fire_time: fire_time,
        dispatched_at: be_within(1.second).of(Time.current),
        node_id: 'node-1',
        status: 'dispatched'
      )
      expect(result).to eq(dispatch_record)
    end

    it 'allows custom status' do
      fire_time = Time.current
      dispatch_record = instance_double(RailsCron::CronDispatch)
      allow(cron_dispatch_class).to receive(:create!).and_return(dispatch_record)

      result = engine.log_dispatch('daily_report', fire_time, 'node-1', 'failed')

      expect(cron_dispatch_class).to have_received(:create!).with(
        key: 'daily_report',
        fire_time: fire_time,
        dispatched_at: be_within(1.second).of(Time.current),
        node_id: 'node-1',
        status: 'failed'
      )
      expect(result).to eq(dispatch_record)
    end

    it 'raises error if record is invalid' do
      fire_time = Time.current
      allow(cron_dispatch_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect do
        engine.log_dispatch('daily_report', fire_time, 'node-1')
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#find_dispatch' do
    it 'finds dispatch record by key and fire_time' do
      fire_time = Time.current
      dispatch_record = instance_double(RailsCron::CronDispatch)
      allow(cron_dispatch_class).to receive(:find_by).and_return(dispatch_record)

      result = engine.find_dispatch('daily_report', fire_time)

      expect(cron_dispatch_class).to have_received(:find_by).with(
        key: 'daily_report',
        fire_time: fire_time
      )
      expect(result).to eq(dispatch_record)
    end

    it 'returns nil when record does not exist' do
      fire_time = Time.current
      allow(cron_dispatch_class).to receive(:find_by).and_return(nil)

      result = engine.find_dispatch('nonexistent', fire_time)

      expect(cron_dispatch_class).to have_received(:find_by).with(
        key: 'nonexistent',
        fire_time: fire_time
      )
      expect(result).to be_nil
    end
  end

  describe '#dispatched?' do
    it 'returns true when dispatch exists' do
      fire_time = Time.current
      dispatch_record = instance_double(RailsCron::CronDispatch)
      allow(cron_dispatch_class).to receive(:find_by).and_return(dispatch_record)

      expect(engine.dispatched?('test_key', fire_time)).to be true
    end

    it 'returns false when dispatch does not exist' do
      fire_time = Time.current
      allow(cron_dispatch_class).to receive(:find_by).and_return(nil)

      expect(engine.dispatched?('test_key', fire_time)).to be false
    end
  end

  describe '#find_by_key' do
    it 'returns sorted collection of dispatches for a key' do
      relation = instance_double(ActiveRecord::Relation)
      ordered_relation = instance_double(ActiveRecord::Relation)
      allow(cron_dispatch_class).to receive(:where).and_return(relation)
      allow(relation).to receive(:order).and_return(ordered_relation)

      result = engine.find_by_key('daily_report')

      expect(cron_dispatch_class).to have_received(:where).with(key: 'daily_report')
      expect(relation).to have_received(:order).with(fire_time: :desc)
      expect(result).to eq(ordered_relation)
    end
  end

  describe '#find_by_node' do
    it 'returns sorted collection of dispatches for a node' do
      relation = instance_double(ActiveRecord::Relation)
      ordered_relation = instance_double(ActiveRecord::Relation)
      allow(cron_dispatch_class).to receive(:where).and_return(relation)
      allow(relation).to receive(:order).and_return(ordered_relation)

      result = engine.find_by_node('node-1')

      expect(cron_dispatch_class).to have_received(:where).with(node_id: 'node-1')
      expect(relation).to have_received(:order).with(fire_time: :desc)
      expect(result).to eq(ordered_relation)
    end
  end

  describe '#find_by_status' do
    it 'returns sorted collection of dispatches with status' do
      relation = instance_double(ActiveRecord::Relation)
      ordered_relation = instance_double(ActiveRecord::Relation)
      allow(cron_dispatch_class).to receive(:where).and_return(relation)
      allow(relation).to receive(:order).and_return(ordered_relation)

      result = engine.find_by_status('failed')

      expect(cron_dispatch_class).to have_received(:where).with(status: 'failed')
      expect(relation).to have_received(:order).with(fire_time: :desc)
      expect(result).to eq(ordered_relation)
    end
  end

  describe '#cleanup' do
    it 'deletes dispatch records older than recovery_window' do
      recovery_window = 86_400 # 24 hours
      relation = instance_double(ActiveRecord::Relation)
      allow(cron_dispatch_class).to receive(:where).and_return(relation)
      allow(relation).to receive(:delete_all).and_return(42)
      time_now = Time.current
      allow(Time).to receive(:current).and_return(time_now)
      cutoff_time = time_now - recovery_window

      result = engine.cleanup(recovery_window: recovery_window)

      expect(cron_dispatch_class).to have_received(:where).with('fire_time < ?', be_within(1.second).of(cutoff_time))
      expect(relation).to have_received(:delete_all)
      expect(result).to eq(42)
    end

    it 'returns number of deleted records' do
      relation = instance_double(ActiveRecord::Relation)
      allow(cron_dispatch_class).to receive(:where).and_return(relation)
      allow(relation).to receive(:delete_all).and_return(25)

      result = engine.cleanup(recovery_window: 3600)

      expect(result).to eq(25)
    end

    it 'uses default 86400 seconds (24 hours) if no recovery_window provided' do
      relation = instance_double(ActiveRecord::Relation)
      allow(cron_dispatch_class).to receive(:where).and_return(relation)
      allow(relation).to receive(:delete_all).and_return(10)
      time_now = Time.current
      allow(Time).to receive(:current).and_return(time_now)

      engine.cleanup

      expect(cron_dispatch_class).to have_received(:where) do |sql, time|
        expect(sql).to eq('fire_time < ?')
        expect(time).to be_within(1.second).of(time_now - 86_400)
      end
      expect(relation).to have_received(:delete_all)
    end

    it 'handles empty result gracefully' do
      relation = instance_double(ActiveRecord::Relation)
      allow(cron_dispatch_class).to receive(:where).and_return(relation)
      allow(relation).to receive(:delete_all).and_return(0)

      result = engine.cleanup(recovery_window: 3600)

      expect(result).to eq(0)
    end

    it 'handles database errors during cleanup' do
      allow(cron_dispatch_class).to receive(:where).and_raise(StandardError, 'Database error')

      expect { engine.cleanup(recovery_window: 3600) }.to raise_error(StandardError)
    end
  end
end
