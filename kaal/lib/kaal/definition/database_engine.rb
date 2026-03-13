# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require_relative 'registry'

module Kaal
  module Definition
    # ActiveRecord-backed definition registry persisted in kaal_definitions.
    class DatabaseEngine < Registry
      def initialize
        super
        @definition_model = ::Kaal::CronDefinition
      end

      def upsert_definition(key:, cron:, enabled: true, source: 'code', metadata: {})
        @definition_model.upsert_definition!(
          key: key,
          cron: cron,
          enabled: enabled,
          source: source,
          metadata: metadata
        ).to_definition_hash
      end

      def remove_definition(key)
        record = @definition_model.find_by(key: key)
        return nil unless record

        record.destroy_and_return_definition_hash
      end

      def find_definition(key)
        record = @definition_model.find_by(key: key)
        record&.to_definition_hash
      end

      def all_definitions
        @definition_model.order(:key).map(&:to_definition_hash)
      end

      def enabled_definitions
        @definition_model.where(enabled: true).order(:key).map(&:to_definition_hash)
      end
    end
  end
end
