# frozen_string_literal: true

require 'active_support/core_ext/object/deep_dup'
require_relative 'registry'

module RailsCron
  module Definition
    # In-memory definition registry used when no persistent backend is configured.
    class MemoryEngine < Registry
      def initialize
        super
        @definitions = {}
        @mutex = Mutex.new
      end

      def upsert_definition(key:, cron:, enabled: true, source: 'code', metadata: {})
        @mutex.synchronize do
          now = Time.current
          existing = @definitions[key]
          definition = {
            key: key,
            cron: cron,
            enabled: enabled,
            source: source,
            metadata: metadata,
            created_at: existing ? existing[:created_at] : now,
            updated_at: now,
            disabled_at: enabled ? nil : now
          }
          @definitions[key] = definition

          definition.deep_dup
        end
      end

      def remove_definition(key)
        @mutex.synchronize { @definitions.delete(key)&.deep_dup }
      end

      def find_definition(key)
        @mutex.synchronize { @definitions[key]&.deep_dup }
      end

      def all_definitions
        @mutex.synchronize { @definitions.values.map(&:deep_dup) }
      end

      def clear
        @mutex.synchronize { @definitions.clear }
      end
    end
  end
end
