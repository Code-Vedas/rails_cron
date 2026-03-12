# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.shared_examples 'scheduler lifecycle integration' do
  include IntegrationSchedulerHelper

  it 'dispatches code-defined and file-defined jobs for the same tick' do
    recorder = build_event_recorder
    build_inline_job_class(recorder)

    code_key = scheduler_key('source-code')
    file_key = scheduler_key('source-file')

    register_code_job(key: code_key, recorder:, source: 'code')
    write_scheduler_config(file_job_definition(key: file_key))
    Kaal.load_scheduler_file!

    tick_time = integration_tick_time
    tick_scheduler(at: tick_time)

    events = recorder.wait_for_count(2)

    expect(events.map { |event| event[:key] }).to contain_exactly(code_key, file_key)
    expect(events.map { |event| event[:source] }).to contain_exactly('code', 'file')
    expect(events.map { |event| event[:fire_time] }.uniq).to eq([expected_fire_time(tick_time)])
    expect(Kaal.definition_registry.find_definition(code_key)).to include(source: 'code', enabled: true)
    expect(Kaal.definition_registry.find_definition(file_key)).to include(source: 'file', enabled: true)
  end

  it 'does not dispatch disabled definitions and resumes after re-enable' do
    recorder = build_event_recorder
    key = scheduler_key('toggle')

    register_code_job(key: key, recorder:)
    Kaal.disable(key:)

    tick_scheduler(at: integration_tick_time)

    expect(recorder.snapshot).to be_empty
    expect(Kaal.definition_registry.find_definition(key)).to include(enabled: false)

    Kaal.enable(key:)
    tick_time = integration_tick_time(1)
    tick_scheduler(at: tick_time)

    events = recorder.wait_for_count(1)
    expect(events.first).to include(key:, source: 'code', fire_time: expected_fire_time(tick_time))
    expect(Kaal.definition_registry.find_definition(key)).to include(enabled: true)
  end

  it 'dispatches again after the coordinator is rebuilt with the same callbacks' do
    recorder = build_event_recorder
    key = scheduler_key('restart')

    register_code_job(key: key, recorder:)

    first_tick = integration_tick_time
    tick_scheduler(at: first_tick)

    original_coordinator = Kaal.coordinator
    Kaal.reset_coordinator!

    second_tick = integration_tick_time(1)
    tick_scheduler(at: second_tick)

    events = recorder.wait_for_count(2)

    expect(Kaal.coordinator).not_to be(original_coordinator)
    expect(events.map { |event| event[:fire_time] }).to contain_exactly(
      expected_fire_time(first_tick),
      expected_fire_time(second_tick)
    )
  end
end

RSpec.shared_examples 'shared store scheduler lifecycle integration' do
  include IntegrationSchedulerHelper

  it 'shares enabled definition state across coordinators backed by the same store' do
    recorder_one = build_event_recorder
    recorder_two = build_event_recorder
    key = scheduler_key('shared-store')
    definition_registry = Kaal.definition_registry

    definition_registry.upsert_definition(key: key, cron: '* * * * *', enabled: true, source: 'code', metadata: {})

    registry_one = Kaal::Registry.new
    registry_two = Kaal::Registry.new

    registry_one.add(
      key: key,
      cron: '* * * * *',
      enqueue: lambda do |fire_time:, idempotency_key:|
        recorder_one.record(key: key, source: 'node-1', fire_time: fire_time.utc, idempotency_key:)
      end
    )
    registry_two.add(
      key: key,
      cron: '* * * * *',
      enqueue: lambda do |fire_time:, idempotency_key:|
        recorder_two.record(key: key, source: 'node-2', fire_time: fire_time.utc, idempotency_key:)
      end
    )

    coordinator_one = build_coordinator(adapter_instance:, registry: registry_one)
    coordinator_two = build_coordinator(adapter_instance:, registry: registry_two)

    first_tick = integration_tick_time
    tick_scheduler(at: first_tick, coordinator: coordinator_one)
    expect(recorder_one.wait_for_count(1).first).to include(source: 'node-1', fire_time: expected_fire_time(first_tick))

    second_tick = integration_tick_time(2)
    tick_scheduler(at: second_tick, coordinator: coordinator_two)
    expect(definition_registry.find_definition(key)).to include(enabled: true)
    expect(recorder_two.wait_for_count(1).first).to include(source: 'node-2', fire_time: expected_fire_time(second_tick))
  end
end
