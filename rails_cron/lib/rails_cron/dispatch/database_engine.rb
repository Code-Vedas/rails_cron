# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'registry'

module RailsCron
  module Dispatch
    ##
    # Database-backed dispatch registry using ActiveRecord.
    #
    # Stores dispatch records in the database using the CronDispatch model.
    # Provides persistent, queryable audit logs across all nodes.
    #
    # @example Usage
    #   registry = RailsCron::Dispatch::DatabaseEngine.new
    #   registry.log_dispatch('daily_report', Time.current, 'node-1')
    #   registry.dispatched?('daily_report', Time.current) # => true
    class DatabaseEngine < Registry
      ##
      # Log a dispatch attempt in the database.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @param node_id [String] identifier for the dispatching node
      # @param status [String] dispatch status ('dispatched', 'failed', etc.)
      # @return [RailsCron::CronDispatch] the created dispatch record
      # @raise [ActiveRecord::RecordInvalid] if the record is invalid
      def log_dispatch(key, fire_time, node_id, status = 'dispatched')
        ::RailsCron::CronDispatch.create!(
          key: key,
          fire_time: fire_time,
          dispatched_at: Time.current,
          node_id: node_id,
          status: status
        )
      end

      ##
      # Find a dispatch record for a specific job and fire time.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @return [RailsCron::CronDispatch, nil] dispatch record or nil if not found
      def find_dispatch(key, fire_time)
        ::RailsCron::CronDispatch.find_by(key: key, fire_time: fire_time)
      end

      ##
      # Find all dispatch records for a specific job key.
      #
      # @param key [String] the cron job key
      # @return [ActiveRecord::Relation] collection of dispatch records
      def find_by_key(key)
        ::RailsCron::CronDispatch.where(key: key).order(fire_time: :desc)
      end

      ##
      # Find all dispatch records by node ID.
      #
      # @param node_id [String] the node identifier
      # @return [ActiveRecord::Relation] collection of dispatch records
      def find_by_node(node_id)
        ::RailsCron::CronDispatch.where(node_id: node_id).order(fire_time: :desc)
      end

      ##
      # Find all dispatch records with a specific status.
      #
      # @param status [String] the dispatch status
      # @return [ActiveRecord::Relation] collection of dispatch records
      def find_by_status(status)
        ::RailsCron::CronDispatch.where(status: status).order(fire_time: :desc)
      end

      ##
      # Delete old dispatch records older than the specified time.
      #
      # This cleanup prevents unbounded database growth by removing records
      # that are older than the recovery window, making them irrelevant for
      # future recovery operations.
      #
      # @param recovery_window [Integer] seconds to keep records for (e.g., 86400 for 24h)
      # @return [Integer] number of records deleted
      def cleanup(recovery_window: 86_400)
        cutoff_time = Time.current - recovery_window
        ::RailsCron::CronDispatch.where('fire_time < ?', cutoff_time).delete_all
      end
    end
  end
end
