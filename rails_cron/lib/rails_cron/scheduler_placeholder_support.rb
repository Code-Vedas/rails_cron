# frozen_string_literal: true

module RailsCron
  # Placeholder parsing/resolution for scheduler args and kwargs.
  module SchedulerPlaceholderSupport
    private

    def validate_placeholders(input, key:)
      case input
      when String
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
      if (match = text.match(/\A\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}\z/))
        return @placeholder_resolvers.fetch(match[1]).call(context)
      end

      text.gsub(self.class::PLACEHOLDER_PATTERN) do
        token = Regexp.last_match(1)
        @placeholder_resolvers.fetch(token).call(context).to_s
      end
    end

    def validate_placeholder_key(hash_key, key:)
      return unless hash_key.is_a?(String)

      token = hash_key.scan(self.class::PLACEHOLDER_PATTERN).flatten.first
      return unless token

      raise SchedulerConfigError, "Placeholders are not supported in hash keys (got '{{#{token}}}' under '#{key}')"
    end
  end
end
