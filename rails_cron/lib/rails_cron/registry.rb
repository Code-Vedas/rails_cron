# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

module RailsCron
  ##
  # Thread-safe registry for storing and managing registered cron jobs.
  # Each entry consists of a unique key, cron expression, and enqueue callback.
  #
  # @example Register a job
  #   registry = RailsCron::Registry.new
  #   registry.add("reports:daily", "0 9 * * *", ->(fire_time:, idempotency_key:) { })
  #
  # @example Retrieve all jobs
  #   registry.all # => [{ key: "reports:daily", cron: "0 9 * * *", enqueue: Proc }]
  class Registry
    include Enumerable

    ##
    # Entry class representing a single registered cron job
    Entry = Struct.new(:key, :cron, :enqueue, keyword_init: true)

    ##
    # Initialize a new Registry instance.
    def initialize
      @entries = {}
      @mutex = Mutex.new
    end

    ##
    # Register a new cron job.
    #
    # Entries are frozen after creation to prevent external mutation
    # that could corrupt the internal key->entry mapping.
    #
    # @param key [String] unique identifier for the cron task
    # @param cron [String] cron expression (e.g., "0 9 * * *", "@daily")
    # @param enqueue [Proc, Lambda] callable that executes when cron fires
    # @return [Entry] the registered entry (frozen)
    #
    # @raise [ArgumentError] if key is empty, cron is empty, or enqueue is not callable
    # @raise [RegistryError] if key is already registered
    #
    # @example
    #   registry.add(
    #     key: "job:daily",
    #     cron: "0 9 * * *",
    #     enqueue: ->(fire_time:, idempotency_key:) { MyJob.perform_later }
    #   )
    def add(key, cron, enqueue)
      validate_entry(key, cron, enqueue)

      @mutex.synchronize do
        raise RegistryError, "Key '#{key}' is already registered" if @entries.key?(key)

        entry = Entry.new(key: key, cron: cron, enqueue: enqueue).freeze
        @entries[key] = entry
        entry
      end
    end

    ##
    # Unregister (remove) a cron job by key.
    #
    # @param key [String] the key to unregister
    # @return [Entry, nil] the removed entry, or nil if not found
    #
    # @example
    #   registry.remove("job:daily")
    def remove(key)
      @mutex.synchronize do
        @entries.delete(key)
      end
    end

    ##
    # Find a registered entry by key.
    #
    # @param key [String] the key to look up
    # @return [Entry, nil] the entry if found, nil otherwise
    #
    # @example
    #   entry = registry.find("job:daily")
    #   entry.cron # => "0 9 * * *"
    def find(key)
      @mutex.synchronize do
        @entries[key]
      end
    end

    ##
    # Get all registered entries.
    #
    # @return [Array<Entry>] a copy of all registered entries
    #
    # @example
    #   all_entries = registry.all
    #   all_entries.each { |entry| puts entry.key }
    def all
      @mutex.synchronize do
        @entries.values.dup
      end
    end

    ##
    # Get the number of registered entries.
    #
    # @return [Integer] the count of registered cron jobs
    #
    # @example
    #   registry.size # => 3
    def size
      @mutex.synchronize do
        @entries.size
      end
    end

    ##
    # Alias for size method.
    #
    # @return [Integer] the count of registered cron jobs
    alias count size

    ##
    # Check if a key is registered.
    #
    # @param key [String] the key to check
    # @return [Boolean] true if the key is registered, false otherwise
    #
    # @example
    #   registry.registered?("job:daily") # => true
    def registered?(key)
      @mutex.synchronize do
        @entries.key?(key)
      end
    end

    ##
    # Clear all registered entries.
    #
    # @return [Integer] the number of entries that were cleared
    #
    # @example
    #   cleared_count = registry.clear
    def clear
      @mutex.synchronize do
        count = @entries.size
        @entries.clear
        count
      end
    end

    ##
    # Iterate over all entries with thread-safe access.
    #
    # Copies entries inside the lock and yields outside to avoid deadlocks
    # if the block calls back into the registry.
    #
    # @yield [entry] yields each entry to the block
    # @yieldparam entry [Entry] the cron entry
    # @return [void]
    #
    # @example
    #   registry.each { |entry| puts entry.key }
    def each(&)
      return enum_for(:each) unless block_given?

      entries_snapshot = @mutex.synchronize do
        @entries.values.dup
      end

      entries_snapshot.each(&)
    end

    ##
    # Convert registry to an array of hashes.
    #
    # @return [Array<Hash>] array of entry details
    #
    # @example
    #   registry.to_a # => [{ key: "job:daily", cron: "0 9 * * *", enqueue: Proc }]
    def to_a
      @mutex.synchronize do
        @entries.values.map(&:to_h)
      end
    end

    ##
    # Get a string representation of the registry.
    #
    # @return [String] human-readable registry summary
    def inspect
      @mutex.synchronize do
        "#<RailsCron::Registry size=#{@entries.size} keys=[#{@entries.keys.map(&:inspect).join(', ')}]>"
      end
    end

    private

    ##
    # Validate entry parameters before adding to registry.
    #
    # @param key [String] the key to validate
    # @param cron [String] the cron expression to validate
    # @param enqueue [Proc, Lambda] the enqueue callback to validate
    # @raise [ArgumentError] if any parameter is invalid
    def validate_entry(key, cron, enqueue)
      raise ArgumentError, 'key cannot be empty' if key.to_s.strip.empty?
      raise ArgumentError, 'cron cannot be empty' if cron.to_s.strip.empty?
      raise ArgumentError, 'enqueue must be callable' unless callable?(enqueue)
    end

    def callable?(enqueue)
      enqueue.respond_to?(:call)
    end
  end

  ##
  # Error raised when registry operations fail.
  class RegistryError < StandardError; end
end
