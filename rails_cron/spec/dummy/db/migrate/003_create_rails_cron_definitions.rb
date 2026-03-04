# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

class CreateRailsCronDefinitions < ActiveRecord::Migration[7.0]
  def change
    create_table :rails_cron_definitions do |t|
      t.string :key, null: false, limit: 255
      t.string :cron, null: false, limit: 255
      t.boolean :enabled, null: false, default: true
      t.string :source, null: false, limit: 50, default: 'code'
      t.json :metadata, null: false
      t.datetime :disabled_at

      t.timestamps
    end

    add_index :rails_cron_definitions, :key, unique: true
    add_index :rails_cron_definitions, :enabled
    add_index :rails_cron_definitions, :source
  end
end
