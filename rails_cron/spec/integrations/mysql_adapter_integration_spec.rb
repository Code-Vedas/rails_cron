# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rails_helper'

RSpec.describe 'Lock integration', integration: 'mysql' do # rubocop:disable RSpec/DescribeClass
  include IntegrationLockHelper

  let(:adapter_label) { 'mysql' }
  let(:adapter_instance) { RailsCron::Lock::MySQLAdapter.new }

  before do
    configure_lock_adapter(adapter_instance, adapter_label)
  end

  after do
    cleanup_lock_keys(adapter_label)
    restore_lock_adapter
  end

  it_behaves_like 'lock adapter integration'
end
