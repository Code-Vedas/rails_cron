# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  ##
  # Model for distributed lock records (database-backed).
  #
  # Used by the database-backed adapter (SQLiteAdapter) to store lock state in a database table.
  # Works with any ActiveRecord-supported SQL database (SQLite, PostgreSQL, MySQL, etc.).
  # Each row represents a held lock with an expiration time.
  class CronLock < ApplicationRecord
    self.table_name = 'rails_cron_locks'

    validates :key, presence: true, uniqueness: true
    validates :acquired_at, presence: true
    validates :expires_at, presence: true

    ##
    # Find and delete any expired locks (cleanup).
    #
    # @return [Integer] number of locks deleted
    def self.cleanup_expired
      where('expires_at < ?', Time.current).delete_all
    end

    ##
    # Check if this lock is still valid (not expired).
    #
    # @return [Boolean] true if not expired
    def not_expired?
      expires_at > Time.current
    end
  end
end
