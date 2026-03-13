# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  # Register conflict handling helpers shared by Kaal singleton methods.
  module RegisterConflictSupport
    private

    def resolve_register_conflict(key:, cron:, enqueue:, existing_definition:, existing_entry:)
      return unless existing_definition&.[](:source).to_s == 'file'

      policy = configuration.scheduler_conflict_policy
      case policy
      when :error
        raise RegistryError, "Key '#{key}' is already registered by scheduler file"
      when :file_wins
        configuration.logger&.warn("Skipping code registration for '#{key}' because scheduler_conflict_policy is :file_wins")
        existing_entry
      when :code_wins
        replace_file_registered_definition(
          key: key,
          cron: cron,
          enqueue: enqueue,
          existing_definition: existing_definition
        )
      else
        raise SchedulerConfigError, "Unsupported scheduler_conflict_policy '#{policy}'"
      end
    end

    def replace_file_registered_definition(key:, cron:, enqueue:, existing_definition:)
      persisted_attributes = {
        enabled: existing_definition.fetch(:enabled, true),
        source: 'code',
        metadata: existing_definition.fetch(:metadata, {})
      }
      definition_registry.upsert_definition(key: key, cron: cron, **persisted_attributes)
      with_registered_definition_rollback(key, existing_definition) do
        registry.upsert(key: key, cron: cron, enqueue: enqueue)
      end
    end

    def with_registered_definition_rollback(key, existing_definition)
      yield
    rescue StandardError
      begin
        rollback_registered_definition(key, existing_definition)
      rescue StandardError => rollback_error
        configuration.logger&.error("Failed to rollback persisted definition for #{key}: #{rollback_error.message}")
      end

      raise
    end
  end
end
