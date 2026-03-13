# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  # Persistent scheduler definition model.
  class CronDefinition < ApplicationRecord
    self.table_name = 'kaal_definitions'

    before_validation :ensure_metadata

    validates :key, presence: true, uniqueness: true
    validates :cron, presence: true
    validates :source, presence: true
    validates :enabled, inclusion: { in: [true, false] }

    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :by_source, ->(source) { where(source: source) }

    def self.upsert_definition!(key:, cron:, enabled:, source:, metadata:)
      persist_definition(find_or_initialize_by(key: key), cron:, enabled:, source:, metadata:)
    rescue ActiveRecord::RecordNotUnique
      persist_definition(find_by!(key: key), cron:, enabled:, source:, metadata:)
    end

    def to_definition_hash
      {
        key: key,
        cron: cron,
        enabled: enabled,
        source: source,
        metadata: metadata || {},
        created_at: created_at,
        updated_at: updated_at,
        disabled_at: disabled_at
      }
    end

    def destroy_and_return_definition_hash
      definition_hash = to_definition_hash
      destroy!
      definition_hash
    end

    def self.persist_definition(record, cron:, enabled:, source:, metadata:)
      disabled_at = if enabled
                      nil
                    elsif record.new_record? || record.enabled != false
                      Time.current
                    else
                      record.disabled_at
                    end

      record.assign_attributes(
        cron: cron,
        enabled: enabled,
        source: source,
        metadata: metadata,
        disabled_at:
      )
      record.save!
      record
    end
    private_class_method :persist_definition

    private

    def ensure_metadata
      self.metadata ||= {}
    end
  end
end
