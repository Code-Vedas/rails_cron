# frozen_string_literal: true

require 'erb'
require 'pathname'
require 'yaml'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/object/deep_dup'
require 'active_support/core_ext/string/inflections'

module RailsCron
  # Loads scheduler definitions from config/scheduler.yml and registers them.
  class SchedulerFileLoader
    PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/
    ALLOWED_PLACEHOLDERS = {
      'fire_time.iso8601' => ->(ctx) { ctx.fetch(:fire_time).iso8601 },
      'fire_time.unix' => ->(ctx) { ctx.fetch(:fire_time).to_i },
      'idempotency_key' => ->(ctx) { ctx.fetch(:idempotency_key) },
      'key' => ->(ctx) { ctx.fetch(:key) }
    }.freeze
    TO_STRING = :to_s.to_proc
    TO_SYMBOL = :to_sym.to_proc

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
      path = scheduler_file_path
      return handle_missing_file(path) unless File.exist?(path)

      payload = parse_yaml(path)
      jobs = extract_jobs(payload)
      validate_unique_keys(jobs)
      normalized_jobs = jobs.map { |job_payload| normalize_job(job_payload) }
      normalized_jobs.each { |job| apply_job(**job) }

      normalized_jobs
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
      rendered = ERB.new(File.read(path), trim_mode: '-').result
      parsed = YAML.safe_load(rendered, aliases: true) || {}
      raise SchedulerConfigError, "Expected scheduler YAML root to be a mapping in #{path}" unless parsed.is_a?(Hash)

      stringify_keys(parsed)
    rescue Psych::SyntaxError => e
      raise SchedulerConfigError, "Failed to parse scheduler YAML at #{path}: #{e.message}"
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
      key = extract_required_string(payload, field: 'key', error_prefix: 'Job key cannot be blank')
      cron = extract_required_string(payload, field: 'cron', error_prefix: "Job cron cannot be blank for key '#{key}'")
      job_class_name = extract_required_string(
        payload, field: 'job_class', error_prefix: "Job job_class cannot be blank for key '#{key}'"
      )
      validate_cron(key:, cron:)
      options = extract_job_options(payload, key:)

      {
        key:,
        cron:,
        job_class_name:,
        **options
      }
    rescue SchedulerConfigError => e
      raise e unless e.message == 'Job key cannot be blank'

      raise SchedulerConfigError, "Job key cannot be blank: #{payload.inspect}"
    end

    def extract_required_string(payload, field:, error_prefix:)
      value = payload.fetch(field, '').to_s.strip
      raise SchedulerConfigError, error_prefix if value.empty?

      value
    end

    def validate_cron(key:, cron:)
      return if RailsCron.valid?(cron)

      raise SchedulerConfigError, "Invalid cron expression '#{cron}' for key '#{key}'"
    end

    def extract_job_options(payload, key:)
      metadata, args, kwargs, queue, enabled_value = payload.values_at('metadata', 'args', 'kwargs', 'queue', 'enabled')
      args ||= []
      kwargs ||= {}
      enabled = if payload.key?('enabled')
                  enabled_value ? true : false
                else
                  true
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
      return if skip_due_to_conflict?(key:, existing_definition:)

      callback = build_callback(
        key: key,
        job_class_name: job_class_name,
        queue: queue,
        args_template: args,
        kwargs_template: kwargs
      )
      persisted_metadata = metadata.deep_merge(
        execution: {
          target: 'active_job',
          job_class: job_class_name,
          queue: queue,
          args: args,
          kwargs: kwargs
        }
      )

      @definition_registry.upsert_definition(
        key: key,
        cron: cron,
        enabled: enabled,
        source: 'file',
        metadata: persisted_metadata
      )

      @registry.remove(key) if @registry.registered?(key)
      @registry.add(key: key, cron: cron, enqueue: callback)
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
        resolved_kwargs = symbolize_keys_deep(resolve_placeholders(kwargs_template.deep_dup, context))

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

    def validate_placeholders(input, key:)
      case input
      when String
        input.scan(PLACEHOLDER_PATTERN).flatten.each do |token|
          next if @placeholder_resolvers.key?(token)

          raise SchedulerConfigError, "Unknown placeholder '{{#{token}}}' for key '#{key}'"
        end
      when Array
        input.each { |item| validate_placeholders(item, key:) }
      when Hash
        input.each_value { |child| validate_placeholders(child, key:) }
      end
    end

    def resolve_placeholders(template, context)
      case template
      when String
        replace_placeholders(template, context)
      when Array
        template.map { |item| resolve_placeholders(item, context) }
      when Hash
        template.transform_values { |child| resolve_placeholders(child, context) }
      else
        template
      end
    end

    def replace_placeholders(text, context)
      if (match = text.match(/\A\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}\z/))
        return @placeholder_resolvers.fetch(match[1]).call(context)
      end

      text.gsub(PLACEHOLDER_PATTERN) do
        token = Regexp.last_match(1)
        @placeholder_resolvers.fetch(token).call(context).to_s
      end
    end

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
