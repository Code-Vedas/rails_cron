# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

class CreateRailsCronLocks < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_cron_locks do |t|
      # Lock key (unique identifier for the lock)
      t.string :key, null: false, limit: 255

      # When the lock was acquired
      t.datetime :acquired_at, null: false

      # When the lock expires (acquired_at + ttl)
      t.datetime :expires_at, null: false

      t.timestamps
    end

    # Ensure key is unique (only one lock per key at a time)
    add_index :rails_cron_locks, :key, unique: true

    # Index for cleanup queries (find expired locks)
    add_index :rails_cron_locks, :expires_at
  end
end
