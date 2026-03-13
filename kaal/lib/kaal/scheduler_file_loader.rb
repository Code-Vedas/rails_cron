# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'erb'
require 'pathname'
require 'yaml'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/object/deep_dup'
require 'active_support/core_ext/string/inflections'
require_relative 'scheduler_hash_transform'
require_relative 'scheduler_placeholder_support'

module Kaal
  # Loads scheduler definitions from config/scheduler.yml and registers them.
  class SchedulerFileLoader
    include SchedulerHashTransform
    include SchedulerPlaceholderSupport

    PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/
    ALLOWED_PLACEHOLDERS = {
      'fire_time.iso8601' => ->(ctx) { ctx.fetch(:fire_time).iso8601 },
      'fire_time.unix' => ->(ctx) { ctx.fetch(:fire_time).to_i },
      'idempotency_key' => ->(ctx) { ctx.fetch(:idempotency_key) },
      'key' => ->(ctx) { ctx.fetch(:key) }
    }.freeze

    def initialize(configuration:, definition_registry:, registry:, logger:, rails_context: Rails)
      @configuration = configuration
      @definition_registry = definition_registry
      @registry = registry
      @logger = logger
      @rails_env = rails_context.env.to_s
      @rails_root = rails_context.root
      @placeholder_resolvers = ALLOWED_PLACEHOLDERS
    end

    def load
      applied_job_contexts = []
      path = scheduler_file_path
      return handle_missing_file(path) unless File.exist?(path)

      payload = parse_yaml(path)
      jobs = extract_jobs(payload)
      validate_unique_keys(jobs)
      normalized_jobs = jobs.map { |job_payload| normalize_job(job_payload) }
      applied_jobs = []
      normalized_jobs.each do |job|
        applied_job_context = apply_job(**job)
        next unless applied_job_context

        applied_jobs << job
        applied_job_contexts << applied_job_context
      end

      applied_jobs
    rescue StandardError
      rollback_applied_jobs(applied_job_contexts)
      raise
    end

    private

    def scheduler_file_path
      configured_path = @configuration.scheduler_config_path.to_s.strip
      raise SchedulerConfigError, 'scheduler_config_path cannot be blank' if configured_path.empty?

      path = Pathname.new(configured_path)
      path.absolute? ? path.to_s : @rails_root.join(path).to_s
    end

    def handle_missing_file(path)
      message = "Scheduler file not found at #{path}"
      raise SchedulerConfigError, message if @configuration.scheduler_missing_file_policy == :error

      @logger&.warn(message)
      []
    end

    def parse_yaml(path)
      rendered = render_yaml_erb(path)
      parsed = YAML.safe_load(rendered) || {}
      raise SchedulerConfigError, "Expected scheduler YAML root to be a mapping in #{path}" unless parsed.is_a?(Hash)

      stringify_keys(parsed)
    rescue Psych::Exception => e
      raise SchedulerConfigError, "Failed to parse scheduler YAML at #{path}: #{e.message}"
    end

    def render_yaml_erb(path)
      ERB.new(File.read(path), trim_mode: '-').result
    rescue StandardError, SyntaxError => e
      raise SchedulerConfigError, "Failed to evaluate scheduler ERB at #{path}: #{e.message}"
    end

    def extract_jobs(payload)
      defaults = fetch_hash(payload, 'defaults')
      env_payload = fetch_hash(payload, @rails_env)
      default_jobs = defaults.fetch('jobs', [])
      env_jobs = env_payload.fetch('jobs', [])
      raise SchedulerConfigError, "Expected 'defaults.jobs' to be an array" unless default_jobs.is_a?(Array)
      raise SchedulerConfigError, "Expected '#{@rails_env}.jobs' to be an array" unless env_jobs.is_a?(Array)

      default_jobs + env_jobs
    end

    def fetch_hash(payload, key)
      section = payload.fetch(key)

      raise SchedulerConfigError, "Expected '#{key}' section to be a mapping" unless section.is_a?(Hash)

      section
    rescue KeyError
      {}
    end

    def validate_unique_keys(jobs)
      keys = jobs.map do |job_payload|
        raise SchedulerConfigError, "Each jobs entry must be a mapping, got #{job_payload.class}" unless job_payload.is_a?(Hash)

        stringify_keys(job_payload)['key'].to_s.strip
      end
      duplicates = keys.group_by(&:itself).select { |key, arr| !key.empty? && arr.size > 1 }.keys
      return if duplicates.empty?

      raise SchedulerConfigError, "Duplicate job keys in scheduler file: #{duplicates.join(', ')}"
    end

    def normalize_job(job_payload)
      payload = stringify_keys(job_payload)
      key = payload.fetch('key', '').to_s.strip
      raise SchedulerConfigError, 'Job key cannot be blank' if key.empty?

      cron = extract_required_string(payload, field: 'cron', error_prefix: "Job cron cannot be blank for key '#{key}'")
      job_class_name = extract_required_string(
        payload, field: 'job_class', error_prefix: "Job class cannot be blank for key '#{key}'"
      )
      validate_cron(key:, cron:)
      options = extract_job_options(payload, key:)

      {
        key:,
        cron:,
        job_class_name:,
        **options
      }
    end

    def extract_required_string(payload, field:, error_prefix:)
      value = payload.fetch(field, '').to_s.strip

      raise SchedulerConfigError, error_prefix if value.empty?

      value
    end

    def validate_cron(key:, cron:)
      return if Kaal.valid?(cron)

      raise SchedulerConfigError, "Invalid cron expression '#{cron}' for key '#{key}'"
    end

    def extract_job_options(payload, key:)
      metadata, args, kwargs, queue, enabled_value = payload.values_at('metadata', 'args', 'kwargs', 'queue', 'enabled')
      args ||= []
      kwargs ||= {}
      enabled = true
      if payload.key?('enabled')
        raise SchedulerConfigError, "enabled must be a boolean for key '#{key}'" unless enabled_value.is_a?(TrueClass) || enabled_value.is_a?(FalseClass)

        enabled = enabled_value
      end

      raise SchedulerConfigError, "metadata must be a mapping for key '#{key}'" if metadata && !metadata.is_a?(Hash)

      validate_job_option_types(key:, args:, kwargs:, queue:)

      validate_placeholders(args, key:)
      validate_placeholders(kwargs, key:)

      { queue: queue, args: args.deep_dup, kwargs: kwargs.deep_dup, enabled: enabled, metadata: metadata ? metadata.deep_dup : {} }
    end

    def validate_job_option_types(key:, args:, kwargs:, queue:)
      raise SchedulerConfigError, "args must be an array for key '#{key}'" unless args.is_a?(Array)
      raise SchedulerConfigError, "kwargs must be a mapping for key '#{key}'" unless kwargs.is_a?(Hash)
      raise SchedulerConfigError, "queue must be a string for key '#{key}'" if queue && !queue.is_a?(String)
      return if kwargs.keys.all? { |kwargs_key| kwargs_key.is_a?(String) || kwargs_key.is_a?(Symbol) }

      raise SchedulerConfigError, "kwargs keys must be strings or symbols for key '#{key}'"
    end

    def apply_job(key:, cron:, job_class_name:, queue:, args:, kwargs:, enabled:, metadata:)
      existing_definition = @definition_registry.find_definition(key)
      existing_registry_entry = @registry.find(key)
      return if skip_due_to_conflict?(key:, existing_definition:)

      callback = build_callback(
        key: key,
        job_class_name: job_class_name,
        queue: queue,
        args_template: args,
        kwargs_template: kwargs
      )
      normalized_metadata = stringify_keys(metadata.deep_dup)
      persisted_metadata = normalized_metadata.deep_merge(
        'execution' => {
          'target' => 'active_job',
          'job_class' => job_class_name,
          'queue' => queue,
          'args' => args,
          'kwargs' => kwargs
        }
      )

      @definition_registry.upsert_definition(
        key: key,
        cron: cron,
        enabled: enabled,
        source: 'file',
        metadata: persisted_metadata
      )

      begin
        @registry.upsert(key: key, cron: cron, enqueue: callback)
      rescue StandardError
        rollback_applied_job(key:, existing_definition:, existing_registry_entry:)
        raise
      end

      { key: key, existing_definition: existing_definition, existing_registry_entry: existing_registry_entry }
    end

    def rollback_applied_jobs(applied_job_contexts = [])
      applied_job_contexts.reverse_each do |applied_job_context|
        rollback_applied_job(**applied_job_context)
      end
    end

    def rollback_applied_job(key:, existing_definition:, existing_registry_entry:)
      if existing_definition
        definition_attributes = existing_definition.slice(:key, :cron, :enabled, :source, :metadata)
        @definition_registry.upsert_definition(**definition_attributes)
      else
        @definition_registry.remove_definition(key)
      end

      @registry.remove(key) if @registry.registered?(key)

      return unless existing_registry_entry

      @registry.upsert(
        key: existing_registry_entry.key,
        cron: existing_registry_entry.cron,
        enqueue: existing_registry_entry.enqueue
      )
    rescue StandardError => e
      @logger&.error("Failed to rollback scheduler file application for #{key}: #{e.message}")
    end

    def skip_due_to_conflict?(key:, existing_definition:)
      existing_source = existing_definition&.[](:source)
      return false unless existing_source && existing_source.to_s != 'file'

      policy = @configuration.scheduler_conflict_policy
      case policy
      when :error
        raise SchedulerConfigError, "Scheduler key conflict for '#{key}' with existing source '#{existing_source}'"
      when :code_wins
        @logger&.warn("Skipping scheduler file job '#{key}' because scheduler_conflict_policy is :code_wins")
        true
      when :file_wins
        false
      else
        raise SchedulerConfigError, "Unsupported scheduler_conflict_policy '#{policy}'"
      end
    end

    def build_callback(key:, job_class_name:, queue:, args_template:, kwargs_template:)
      job_class = resolve_job_class(job_class_name:, key:)
      lambda do |fire_time:, idempotency_key:|
        context = {
          fire_time: fire_time,
          idempotency_key: idempotency_key,
          key: key
        }
        resolved_args = resolve_placeholders(args_template.deep_dup, context)
        raw_kwargs = resolve_placeholders(kwargs_template.deep_dup, context) || {}
        raise SchedulerConfigError, "kwargs for scheduler job '#{key}' must be a mapping, got #{raw_kwargs.class}" unless raw_kwargs.is_a?(Hash)

        keys = raw_kwargs.keys
        index = 0
        while index < keys.length
          kwargs_key = keys[index]
          unless kwargs_key.is_a?(String) || kwargs_key.is_a?(Symbol)
            raise SchedulerConfigError,
                  "Invalid keyword argument key #{kwargs_key.inspect} (#{kwargs_key.class}) for scheduler job '#{key}'"
          end

          index += 1
        end

        resolved_kwargs = raw_kwargs.transform_keys(&:to_sym)

        target = queue ? job_class.set(queue: queue) : job_class
        target.perform_later(*resolved_args, **resolved_kwargs)
      end
    end

    def resolve_job_class(job_class_name:, key:)
      job_class = job_class_name.safe_constantize
      raise SchedulerConfigError, "Unknown job_class '#{job_class_name}' for key '#{key}'" unless job_class
      raise SchedulerConfigError, "job_class '#{job_class_name}' must inherit from ActiveJob::Base for key '#{key}'" unless job_class <= ActiveJob::Base

      job_class
    end
  end
end
