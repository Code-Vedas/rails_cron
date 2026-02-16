# frozen_string_literal: true

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

ActiveRecord::Schema[7.2].define(version: 2) do
  create_table 'rails_cron_dispatches', force: :cascade do |t|
    t.datetime 'created_at', null: false
    t.datetime 'dispatched_at', null: false
    t.datetime 'fire_time', null: false
    t.string 'key', limit: 255, null: false
    t.string 'node_id', limit: 255, null: false
    t.string 'status', limit: 50, default: 'dispatched', null: false
    t.datetime 'updated_at', null: false
    t.index ['dispatched_at'], name: 'index_rails_cron_dispatches_on_dispatched_at'
    t.index %w[key fire_time], name: 'index_rails_cron_dispatches_on_key_and_fire_time', unique: true
    t.index ['status'], name: 'index_rails_cron_dispatches_on_status'
  end

  create_table 'rails_cron_locks', force: :cascade do |t|
    t.datetime 'acquired_at', null: false
    t.datetime 'created_at', null: false
    t.datetime 'expires_at', null: false
    t.string 'key', limit: 255, null: false
    t.datetime 'updated_at', null: false
    t.index ['expires_at'], name: 'index_rails_cron_locks_on_expires_at'
    t.index ['key'], name: 'index_rails_cron_locks_on_key', unique: true
  end
end
