# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 3) do
  create_table 'kaal_dispatches', force: :cascade do |t|
    t.datetime 'created_at', null: false
    t.datetime 'dispatched_at', null: false
    t.datetime 'fire_time', null: false
    t.string 'key', limit: 255, null: false
    t.string 'node_id', limit: 255, null: false
    t.string 'status', limit: 50, default: 'dispatched', null: false
    t.datetime 'updated_at', null: false
    t.index ['dispatched_at'], name: 'index_kaal_dispatches_on_dispatched_at'
    t.index %w[key fire_time], name: 'index_kaal_dispatches_on_key_and_fire_time', unique: true
    t.index ['status'], name: 'index_kaal_dispatches_on_status'
  end

  create_table 'kaal_locks', force: :cascade do |t|
    t.datetime 'acquired_at', null: false
    t.datetime 'created_at', null: false
    t.datetime 'expires_at', null: false
    t.string 'key', limit: 255, null: false
    t.datetime 'updated_at', null: false
    t.index ['expires_at'], name: 'index_kaal_locks_on_expires_at'
    t.index ['key'], name: 'index_kaal_locks_on_key', unique: true
  end

  create_table 'kaal_definitions', force: :cascade do |t|
    t.string 'key', limit: 255, null: false
    t.string 'cron', limit: 255, null: false
    t.boolean 'enabled', default: true, null: false
    t.string 'source', limit: 50, default: 'code', null: false
    t.json 'metadata', null: false
    t.datetime 'disabled_at'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['enabled'], name: 'index_kaal_definitions_on_enabled'
    t.index ['key'], name: 'index_kaal_definitions_on_key', unique: true
    t.index ['source'], name: 'index_kaal_definitions_on_source'
  end
end
