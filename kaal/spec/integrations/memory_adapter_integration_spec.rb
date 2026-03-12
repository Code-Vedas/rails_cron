# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails_helper'

RSpec.describe 'Adapter integration', integration: 'memory' do # rubocop:disable RSpec/DescribeClass
  include IntegrationLockHelper
  include IntegrationSchedulerHelper

  let(:adapter_label) { 'memory' }
  let(:adapter_instance) { Kaal::Backend::MemoryAdapter.new }

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
end
