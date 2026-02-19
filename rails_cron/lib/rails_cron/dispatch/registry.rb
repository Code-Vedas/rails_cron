# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  module Dispatch
    ##
    # Base abstraction for dispatch audit logging.
    #
    # Provides a pluggable interface for logging cron job dispatch attempts
    # across different storage backends (memory, Redis, database, etc.).
    #
    # @example Implementing a custom registry
    #   class MyRegistry < RailsCron::Dispatch::Registry
    #     def log_dispatch(key, fire_time, node_id, status = 'dispatched')
    #       # Your custom implementation
    #     end
    #
    #     def find_dispatch(key, fire_time)
    #       # Your custom implementation
    #     end
    #   end
    class Registry
      ##
      # Log a dispatch attempt for a cron job.
      #
      # @param key [String] the cron job key (without namespace prefix)
      # @param fire_time [Time] when the job was scheduled to fire
      # @param node_id [String] identifier for the dispatching node
      # @param status [String] dispatch status ('dispatched', 'failed', etc.)
      # @raise [NotImplementedError] if not overridden by a subclass
      # @return [void]
      def log_dispatch(_key, _fire_time, _node_id, _status = 'dispatched')
        raise NotImplementedError, "#{self.class.name} must implement #log_dispatch"
      end

      ##
      # Find a dispatch record for a specific job and fire time.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @raise [NotImplementedError] if not overridden by a subclass
      # @return [Hash, nil] dispatch record or nil if not found
      def find_dispatch(_key, _fire_time)
        raise NotImplementedError, "#{self.class.name} must implement #find_dispatch"
      end

      ##
      # Check if a dispatch has been logged for a specific job and fire time.
      #
      # @param key [String] the cron job key
      # @param fire_time [Time] when the job was scheduled to fire
      # @return [Boolean] true if dispatch exists, false otherwise
      def dispatched?(key, fire_time)
        find_dispatch(key, fire_time) ? true : false
      end
    end
  end
end
