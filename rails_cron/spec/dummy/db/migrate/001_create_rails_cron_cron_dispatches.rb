# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

class CreateRailsCronCronDispatches < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_cron_dispatches do |t|
      # Job identifier
      t.string :key, null: false, limit: 255

      # Scheduled fire time for the cron job (use datetime for SQLite compatibility)
      t.datetime :fire_time, null: false

      # Actual time when the job was dispatched
      t.datetime :dispatched_at, null: false

      # Node/host identifier that dispatched the job
      t.string :node_id, null: false, limit: 255

      # Status of the dispatch attempt
      t.string :status, null: false, limit: 50, default: 'dispatched'

      t.timestamps
    end

    # Index for finding dispatches by key and fire_time (prevent duplicates)
    add_index :rails_cron_dispatches, %i[key fire_time], unique: true

    # Index for finding recent dispatches
    add_index :rails_cron_dispatches, :dispatched_at

    # Index for finding dispatches by status
    add_index :rails_cron_dispatches, :status
  end
end
