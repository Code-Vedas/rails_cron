# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  ##
  # Audit model for tracking cron job dispatch attempts across the cluster.
  #
  # CronDispatch records information about each cron job that was dispatched,
  # including the cron key, scheduled fire time, actual dispatch time,
  # the node that dispatched it, and the dispatch status.
  #
  # This model is used by the PostgreSQL lock adapter for observability and
  # debugging in distributed deployments. You can use this table to:
  # - Verify that jobs are only dispatched once per fire_time
  # - Track which node dispatched each job
  # - Monitor dispatch latency
  # - Audit job execution history
  #
  # @example Query dispatch history
  #   RailsCron::CronDispatch.where(
  #     key: 'send_emails',
  #     status: 'dispatched'
  #   ).order(fire_time: :desc).limit(10)
  #
  # @example Find all dispatches from a specific node
  #   RailsCron::CronDispatch.where(node_id: 'worker1').order(dispatched_at: :desc)
  class CronDispatch < ApplicationRecord
    self.table_name = 'rails_cron_dispatches'

    ##
    # Validations
    validates :key, presence: true
    validates :fire_time, presence: true
    validates :dispatched_at, presence: true
    validates :node_id, presence: true
    validates :status, presence: true, inclusion: { in: %w[dispatched failed] }

    ##
    # Scopes for common queries
    scope :recent, ->(limit = 100) { order(dispatched_at: :desc).limit(limit) }
    scope :by_key, ->(key) { where(key: key) }
    scope :by_node, ->(node_id) { where(node_id: node_id) }
    scope :by_status, ->(status) { where(status: status) }
    scope :since, ->(timestamp) { where('dispatched_at >= ?', timestamp) }
  end
end
