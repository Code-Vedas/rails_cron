# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'json'
require_relative 'registry'

module RailsCron
  module Dispatch
    ##
    # Redis-backed dispatch registry.
    #
    # Stores dispatch records in Redis as JSON-serialized values.
    # Keys are automatically expired based on TTL to prevent unbounded growth.
    #
    # @example Usage
    #   redis = Redis.new(url: ENV['REDIS_URL'])
    #   registry = RailsCron::Dispatch::RedisEngine.new(redis, namespace: 'myapp')
    #   registry.log_dispatch('daily_report', Time.current, 'node-1')
    class RedisEngine < Registry
      # Default TTL for dispatch records (7 days in seconds)
      DEFAULT_TTL = 7 * 24 * 60 * 60

      ##
      # Initialize a new Redis-backed registry.
      #
      # @param redis [Redis] Redis client instance
      # @param namespace [String] namespace prefix for Redis keys
      # @param ttl [Integer] TTL in seconds for dispatch records
      def initialize(redis, namespace: 'railscron', ttl: DEFAULT_TTL)
        super()
        @redis = redis
        @namespace = namespace
        @ttl = ttl
      end

      ##
      # Log a dispatch attempt in Redis.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @param node_id [String] identifier for the dispatching node
      # @param status [String] dispatch status ('dispatched', 'failed', etc.)
      # @return [Hash] the stored dispatch record
      def log_dispatch(key, fire_time, node_id, status = 'dispatched')
        redis_key = build_redis_key(key, fire_time)
        record = {
          key: key,
          fire_time: fire_time.to_i,
          dispatched_at: Time.current.to_i,
          node_id: node_id,
          status: status
        }

        @redis.setex(redis_key, @ttl, JSON.generate(record))
        record
      end

      ##
      # Find a dispatch record for a specific job and fire time.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @return [Hash, nil] dispatch record or nil if not found
      def find_dispatch(key, fire_time)
        redis_key = build_redis_key(key, fire_time)
        value = @redis.get(redis_key)
        return nil unless value

        record = JSON.parse(value, symbolize_names: true)
        convert_timestamps(record)
      end

      private

      ##
      # Build a Redis key from job key and fire time.
      #
      # Format: "namespace:cron_dispatch:key:fire_time"
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] the fire time
      # @return [String] Redis key
      def build_redis_key(key, fire_time)
        "#{@namespace}:cron_dispatch:#{key}:#{fire_time.to_i}"
      end

      ##
      # Convert Unix timestamps in record to Time objects.
      #
      # @param record [Hash] the dispatch record with Unix timestamps
      # @return [Hash] the record with Time objects
      def convert_timestamps(record)
        record[:fire_time] = Time.at(record[:fire_time])
        record[:dispatched_at] = Time.at(record[:dispatched_at])
        record
      end
    end
  end
end
