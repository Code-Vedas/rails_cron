# frozen_string_literal: true

module RailsCron
  # Placeholder parsing/resolution for scheduler args and kwargs.
  module SchedulerPlaceholderSupport
    private

    def validate_placeholders(input, key:)
      case input
      when String
        validate_placeholder_syntax(input, key:)
        input.scan(self.class::PLACEHOLDER_PATTERN).flatten.each do |token|
          next if @placeholder_resolvers.key?(token)

          raise SchedulerConfigError, "Unknown placeholder '{{#{token}}}' for key '#{key}'"
        end
      when Array
        input.each { |item| validate_placeholders(item, key:) }
      when Hash
        input.each_pair do |hash_key, child|
          validate_placeholder_key(hash_key, key:)
          validate_placeholders(child, key:)
        end
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
      pattern = self.class::PLACEHOLDER_PATTERN
      anchored_pattern = Regexp.new("\\A#{pattern.source}\\z", pattern.options)
      if (match = text.match(anchored_pattern))
        return @placeholder_resolvers.fetch(match[1]).call(context)
      end

      text.gsub(pattern) do
        token = Regexp.last_match(1)
        @placeholder_resolvers.fetch(token).call(context).to_s
      end
    end

    def validate_placeholder_key(hash_key, key:)
      return unless hash_key.is_a?(String)

      validate_placeholder_syntax(hash_key, key:)

      token = hash_key.scan(self.class::PLACEHOLDER_PATTERN).flatten.first
      return unless token

      raise SchedulerConfigError, "Placeholders are not supported in hash keys (got '{{#{token}}}' under '#{key}')"
    end

    def validate_placeholder_syntax(input, key:)
      raw_placeholders = input.scan(/\{\{.*?\}\}/)
      raw_placeholders.each do |raw_placeholder|
        next if raw_placeholder.match?(placeholder_token_anchors)

        raise SchedulerConfigError, "Malformed placeholder '#{raw_placeholder}' for key '#{key}'"
      end
    end

    def placeholder_token_anchors
      @placeholder_token_anchors ||= begin
        pattern = self.class::PLACEHOLDER_PATTERN
        Regexp.new("\\A#{pattern.source}\\z", pattern.options)
      end
    end
  end
end
