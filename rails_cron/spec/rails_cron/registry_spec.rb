# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe RailsCron::Registry do
  subject(:registry) { described_class.new }

  let(:test_key) { 'test:job' }
  let(:test_cron) { '0 9 * * *' }
  let(:test_enqueue) { ->(fire_time:, idempotency_key:) {} }

  def run_threads(count)
    threads = Array.new(count) { |i| Thread.new { yield(i) } }
    threads.each(&:join)
  end

  def collect_errors(count, &block)
    errors = Queue.new
    run_threads(count) { |i| safe_call(errors, i, &block) }
    errors
  end

  def safe_call(errors, index)
    yield(index)
  rescue StandardError => e
    errors << e
  end

  describe 'initialization' do
    it 'starts with size 0' do
      expect(registry.size).to eq(0)
    end

    it 'starts empty' do
      expect(registry.all).to be_empty
    end
  end

  describe '#add' do
    it 'returns entry with attributes' do
      entry = registry.add(test_key, test_cron, test_enqueue)
      expect(entry).to have_attributes(key: test_key, cron: test_cron, enqueue: test_enqueue)
    end

    it 'increases size' do
      expect { registry.add(test_key, test_cron, test_enqueue) }.to change(registry, :size).from(0).to(1)
    end

    it 'returns a Registry::Entry' do
      entry = registry.add(test_key, test_cron, test_enqueue)
      expect(entry).to be_a(described_class::Entry)
    end

    it 'raises when key is empty' do
      expect { registry.add('', test_cron, test_enqueue) }.to raise_error(ArgumentError, /key cannot be empty/)
    end

    it 'raises when key is whitespace' do
      expect { registry.add('   ', test_cron, test_enqueue) }.to raise_error(ArgumentError, /key cannot be empty/)
    end

    it 'raises when cron is empty' do
      expect { registry.add(test_key, '', test_enqueue) }.to raise_error(ArgumentError, /cron cannot be empty/)
    end

    it 'raises when cron is whitespace' do
      expect { registry.add(test_key, '   ', test_enqueue) }.to raise_error(ArgumentError, /cron cannot be empty/)
    end

    it 'raises when enqueue is not callable' do
      expect { registry.add(test_key, test_cron, 'not callable') }.to raise_error(ArgumentError, /enqueue must be callable/)
    end

    it 'raises when key is already registered' do
      registry.add(test_key, test_cron, test_enqueue)
      expect { registry.add(test_key, '0 10 * * *', test_enqueue) }.to raise_error(RailsCron::RegistryError, /already registered/)
    end

    it 'accepts Proc for enqueue' do
      proc = proc { |fire_time:, idempotency_key:| }
      entry = registry.add(test_key, test_cron, proc)
      expect(entry.enqueue).to eq(proc)
    end

    it 'accepts Method objects for enqueue' do
      method_ref = method(:puts)
      entry = registry.add(test_key, test_cron, method_ref)
      expect(entry.enqueue).to eq(method_ref)
    end

    it 'accepts callable objects for enqueue' do
      callable = Class.new do
        def call(*); end
      end.new

      entry = registry.add(test_key, test_cron, callable)
      expect(entry.enqueue).to eq(callable)
    end
  end

  describe '#remove' do
    before { registry.add(test_key, test_cron, test_enqueue) }

    it 'removes an entry from the registry' do
      expect { registry.remove(test_key) }.to change(registry, :size).from(1).to(0)
    end

    it 'returns the removed entry' do
      entry = registry.remove(test_key)
      expect(entry).to have_attributes(key: test_key, cron: test_cron)
    end

    it "returns nil when key doesn't exist" do
      expect(registry.remove('nonexistent')).to be_nil
    end

    it 'makes the key unregistered' do
      expect { registry.remove(test_key) }.to change { registry.registered?(test_key) }.from(true).to(false)
    end
  end

  describe '#find' do
    before { registry.add(test_key, test_cron, test_enqueue) }

    it 'returns the entry' do
      entry = registry.find(test_key)
      expect(entry).to have_attributes(key: test_key, cron: test_cron)
    end

    it 'returns the same enqueue callback' do
      expect(registry.find(test_key).enqueue).to eq(test_enqueue)
    end

    it "returns nil when entry doesn't exist" do
      expect(registry.find('nonexistent')).to be_nil
    end
  end

  describe '#all' do
    it 'returns an empty array when registry is empty' do
      expect(registry.all).to eq([])
    end

    it 'returns all entries as an array' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      registry.add('job2', '0 10 * * *', test_enqueue)
      expect(registry.all.map(&:key)).to contain_exactly('job1', 'job2')
    end

    it 'returns a copy of the entries' do
      registry.add(test_key, test_cron, test_enqueue)
      expect(registry.all).not_to be(registry.all)
    end
  end

  describe '#size' do
    it 'returns 0 for empty registry' do
      expect(registry.size).to eq(0)
    end

    it 'returns the count of registered entries' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      registry.add('job2', '0 10 * * *', test_enqueue)
      expect(registry.size).to eq(2)
    end

    it 'decreases when entries are removed' do
      registry.add(test_key, test_cron, test_enqueue)
      expect { registry.remove(test_key) }.to change(registry, :size).from(1).to(0)
    end
  end

  describe '#count' do
    it 'matches size' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      expect(registry.count).to eq(registry.size)
    end
  end

  describe '#registered?' do
    it 'returns false for unregistered key' do
      expect(registry.registered?(test_key)).to be(false)
    end

    it 'returns true for registered key' do
      registry.add(test_key, test_cron, test_enqueue)
      expect(registry.registered?(test_key)).to be(true)
    end

    it 'returns false after entry is removed' do
      registry.add(test_key, test_cron, test_enqueue)
      expect { registry.remove(test_key) }.to change { registry.registered?(test_key) }.from(true).to(false)
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      registry.add('job2', '0 10 * * *', test_enqueue)
      expect { registry.clear }.to change(registry, :size).from(2).to(0)
    end

    it 'returns the number of cleared entries' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      registry.add('job2', '0 10 * * *', test_enqueue)
      expect(registry.clear).to eq(2)
    end

    it 'returns 0 when registry is already empty' do
      expect(registry.clear).to eq(0)
    end
  end

  describe '#each' do
    it 'yields nothing for empty registry' do
      expect(registry.map { |entry| entry }).to be_empty
    end

    it 'returns an enumerator when no block is given' do
      expect(registry.each.to_a).to eq([])
    end

    it 'yields each entry' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      registry.add('job2', '0 10 * * *', test_enqueue)
      expect(registry.map(&:key)).to contain_exactly('job1', 'job2')
    end

    it 'is thread-safe' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      entries_seen = []
      Thread.new { registry.each { |entry| entries_seen << entry } }.join
      expect(entries_seen.size).to eq(1)
    end
  end

  describe '#to_a' do
    it 'returns an empty array when registry is empty' do
      expect(registry.to_a).to eq([])
    end

    it 'returns entries as hashes' do
      registry.add(test_key, test_cron, test_enqueue)
      expect(registry.to_a.first).to include(key: test_key, cron: test_cron)
    end
  end

  describe '#inspect' do
    it 'returns a string representation' do
      registry.add('job1', '0 9 * * *', test_enqueue)
      registry.add('job2', '0 10 * * *', test_enqueue)
      expect(registry.inspect).to include('RailsCron::Registry', 'size=2', 'job1', 'job2')
    end

    it 'shows size=0 for empty registry' do
      expect(registry.inspect).to include('size=0')
    end
  end

  describe 'thread safety' do
    it 'handles concurrent additions' do
      run_threads(10) { |i| registry.add("job#{i}", "0 #{i} * * *", test_enqueue) }
      expect(registry.size).to eq(10)
    end

    it 'handles concurrent additions and removals' do
      10.times { |i| registry.add("job#{i}", '0 9 * * *', test_enqueue) }
      run_threads(10) do |i|
        registry.remove("job#{i}")
        registry.add("new_job#{i}", '0 10 * * *', test_enqueue)
      end
      expect(registry.size).to eq(10)
    end

    it 'handles concurrent reads' do
      registry.add(test_key, test_cron, test_enqueue)
      results = Queue.new
      run_threads(10) { results << registry.find(test_key) }
      expect(results.size).to eq(10)
    end

    it 'prevents duplicate key registration under concurrent load' do
      errors = collect_errors(10) { registry.add(test_key, test_cron, test_enqueue) }
      expect([registry.size, errors.size]).to eq([1, 9])
    end
  end

  describe 'Registry::Entry' do
    let(:entry) { described_class::Entry.new(key: test_key, cron: test_cron, enqueue: test_enqueue) }

    it 'is a Struct with keyword arguments' do
      expect(entry).to have_attributes(key: test_key, cron: test_cron, enqueue: test_enqueue)
    end

    it 'can be converted to a hash' do
      expect(entry.to_h).to eq(key: test_key, cron: test_cron, enqueue: test_enqueue)
    end
  end
end
