# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module Kaal
  # Shared deep hash key transformation helpers for scheduler payloads.
  module SchedulerHashTransform
    TO_STRING = :to_s.to_proc
    TO_SYMBOL = ->(key) { key.to_s.to_sym }

    private

    def stringify_keys(object)
      deep_transform(object, key_transform: TO_STRING)
    end

    def symbolize_keys_deep(object)
      deep_transform(object, key_transform: TO_SYMBOL)
    end

    def deep_transform(object, key_transform:)
      case object
      when Hash
        deep_transform_hash(object, key_transform:)
      when Array
        deep_transform_array(object, key_transform:)
      else
        object
      end
    end

    def deep_transform_hash(object, key_transform:)
      object.each_with_object({}) do |(key, child), memo|
        memo[key_transform.call(key)] = deep_transform(child, key_transform:)
      end
    end

    def deep_transform_array(object, key_transform:)
      object.map { |child| deep_transform(child, key_transform:) }
    end
  end
end
