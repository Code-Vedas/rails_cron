# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

RSpec.shared_examples 'lock adapter integration' do
  include IntegrationLockHelper

  it 'executes block and returns result when lock is acquired' do
    key = lock_key('job:single')

    result = backend.with_lock(key, ttl: 30) { 'executed' }

    expect(result).to eq('executed')
  end

  it 'returns nil when lock is already held' do
    key = lock_key('job:contended')

    with_held_lock(key, ttl: 30, hold_for: 0.1) do
      result = backend.with_lock(key, ttl: 30) { 'should_not_execute' }
      expect(result).to be_nil
    end
  end

  it 'allows reacquisition after release' do
    key = lock_key('job:reacquire')

    expect(backend.acquire(key, 30)).to be(true)
    expect(backend.release(key)).to be(true)
    expect(backend.acquire(key, 30)).to be(true)
  ensure
    backend.release(key)
  end

  it 'supports independent locks for different keys' do
    key_a = lock_key('job:a')
    key_b = lock_key('job:b')

    expect(backend.acquire(key_a, 30)).to be(true)
    expect(backend.acquire(key_b, 30)).to be(true)
  ensure
    backend.release(key_a)
    backend.release(key_b)
  end

  it 'releases lock even if block raises' do
    key = lock_key('job:error')

    expect do
      backend.with_lock(key, ttl: 30) { raise 'integration error' }
    end.to raise_error('integration error')

    expect(backend.acquire(key, 30)).to be(true)
  ensure
    backend.release(key)
  end
end
