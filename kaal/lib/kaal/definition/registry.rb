# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  module Definition
    # Base abstraction for cron definition storage.
    class Registry
      def upsert_definition(**)
        raise NotImplementedError, "#{self.class.name} must implement #upsert_definition"
      end

      def remove_definition(_key)
        raise NotImplementedError, "#{self.class.name} must implement #remove_definition"
      end

      def find_definition(_key)
        raise NotImplementedError, "#{self.class.name} must implement #find_definition"
      end

      def all_definitions
        raise NotImplementedError, "#{self.class.name} must implement #all_definitions"
      end

      def enabled_definitions
        all_definitions.select { |definition| definition[:enabled] }
      end

      def enable_definition(key)
        update_definition_enabled_state(key, enabled: true)
      end

      def disable_definition(key)
        update_definition_enabled_state(key, enabled: false)
      end

      private

      def update_definition_enabled_state(key, enabled:)
        definition = find_definition(key)
        return nil unless definition

        attributes = definition.slice(:key, :cron, :source, :metadata).merge(enabled: enabled)
        upsert_definition(**attributes)
      end
    end
  end
end
