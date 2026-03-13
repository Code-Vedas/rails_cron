# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require 'time'
require_relative 'registry'

module Kaal
  module Definition
    # Redis-backed definition registry shared across processes.
    class RedisEngine < Registry
      def initialize(redis, namespace: 'kaal')
        super()
        @redis = redis
        @namespace = namespace
      end

      def upsert_definition(key:, cron:, enabled: true, source: 'code', metadata: {})
        now = Time.current
        existing = find_definition(key)
        payload = {
          key: key,
          cron: cron,
          enabled: enabled,
          source: source,
          metadata: metadata,
          created_at: existing ? existing[:created_at] : now,
          updated_at: now,
          disabled_at: enabled ? nil : now
        }

        @redis.hset(storage_key, key, JSON.generate(self.class.serialize_payload(payload)))
        payload
      end

      def remove_definition(key)
        raw = @redis.hget(storage_key, key)
        @redis.hdel(storage_key, key)
        deserialize(raw)
      end

      def find_definition(key)
        raw = @redis.hget(storage_key, key)
        deserialize(raw)
      end

      def all_definitions
        @redis.hvals(storage_key).filter_map { |raw| self.class.deserialize_payload(raw) }
      end

      private

      def storage_key
        "#{@namespace}:definitions"
      end

      def deserialize(raw)
        self.class.deserialize_payload(raw)
      end

      class << self
        def serialize_payload(payload)
          payload.transform_values do |value|
            value.is_a?(Time) ? value.iso8601 : value
          end
        end

        def deserialize_payload(raw)
          return nil unless raw

          parsed = JSON.parse(raw)
          {
            key: parsed['key'],
            cron: parsed['cron'],
            enabled: parsed['enabled'] == true,
            source: parsed['source'],
            metadata: parsed['metadata'] || {},
            created_at: parse_time(parsed['created_at']),
            updated_at: parse_time(parsed['updated_at']),
            disabled_at: parse_time(parsed['disabled_at'])
          }
        rescue JSON::ParserError
          nil
        end

        def parse_time(value)
          Time.iso8601(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
