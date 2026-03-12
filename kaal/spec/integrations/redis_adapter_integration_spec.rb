# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails_helper'
require 'redis'
require 'securerandom'

RSpec.describe 'Adapter integration', integration: 'redis' do # rubocop:disable RSpec/DescribeClass
  include IntegrationLockHelper
  include IntegrationSchedulerHelper

  let(:adapter_label) { 'redis' }
  let(:adapter_instance) do
    Kaal::Backend::RedisAdapter.new(
      Redis.new(url: ENV.fetch('REDIS_URL')),
      namespace: "kaal-int-#{SecureRandom.hex(4)}"
    )
  end

  before do
    configure_scheduler_backend(adapter_instance, adapter_label)
  end

  after do
    cleanup_scheduler_state(adapter_label)
    cleanup_lock_keys(adapter_label)
    restore_backend
  end

  it_behaves_like 'lock adapter integration'
  it_behaves_like 'scheduler lifecycle integration'
  it_behaves_like 'shared store scheduler lifecycle integration'
end
