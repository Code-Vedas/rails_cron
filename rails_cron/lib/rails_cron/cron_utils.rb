# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fugit'

module RailsCron
  ##
  # Utility helpers for cron expression validation, simplification, and linting.
  module CronUtils
    MACRO_MAP = {
      '@yearly' => '0 0 1 1 *',
      '@annually' => '0 0 1 1 *',
      '@monthly' => '0 0 1 * *',
      '@weekly' => '0 0 * * 0',
      '@daily' => '0 0 * * *',
      '@midnight' => '0 0 * * *',
      '@hourly' => '0 * * * *'
    }.freeze

    CANONICAL_MACROS = {
      '0 0 1 1 *' => '@yearly',
      '0 0 1 * *' => '@monthly',
      '0 0 * * 0' => '@weekly',
      '0 0 * * 7' => '@weekly',
      '0 0 * * *' => '@daily',
      '0 * * * *' => '@hourly'
    }.freeze

    FIELD_SPECS = [
      { name: 'minute', min: 0, max: 59, names: nil },
      { name: 'hour', min: 0, max: 23, names: nil },
      { name: 'day-of-month', min: 1, max: 31, names: nil },
      {
        name: 'month',
        min: 1,
        max: 12,
        names: {
          'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4, 'may' => 5, 'jun' => 6,
          'jul' => 7, 'aug' => 8, 'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12
        }
      },
      {
        name: 'day-of-week',
        min: 0,
        max: 7,
        names: {
          'sun' => 0, 'mon' => 1, 'tue' => 2, 'wed' => 3, 'thu' => 4, 'fri' => 5, 'sat' => 6
        }
      }
    ].freeze

    module_function

    def valid?(expression)
      normalized = normalize(expression)
      return false if normalized.empty?

      return MACRO_MAP.key?(normalized.downcase) if macro?(normalized)

      return false unless five_fields?(normalized)

      !!Fugit.parse_cron(normalized)
    rescue StandardError
      false
    end

    def simplify(expression)
      normalized = safe_normalize(expression)
      raise ArgumentError, invalid_expression_message('') unless normalized

      downcased = normalized.downcase

      if macro?(normalized)
        return canonical_macro_for(downcased) if MACRO_MAP.key?(downcased)

        raise ArgumentError, unsupported_macro_message(normalized)
      end

      raise ArgumentError, invalid_expression_message(normalized) unless valid?(normalized)

      CANONICAL_MACROS.fetch(normalized, normalized)
    end

    def lint(expression)
      normalized = safe_normalize(expression)
      return [invalid_expression_message('')] unless normalized

      invalid_message = invalid_expression_message(normalized)
      return [invalid_message] if normalized.empty?

      if macro?(normalized)
        downcased = normalized.downcase
        return [] if MACRO_MAP.key?(downcased)

        return [unsupported_macro_message(normalized)]
      end

      return [field_count_message(normalized)] unless five_fields?(normalized)

      warnings = normalized.split.each_with_index.flat_map do |field, index|
        lint_field(field, FIELD_SPECS[index])
      end

      warnings << invalid_message unless valid?(normalized)
      warnings.uniq
    end

    def lint_field(field, spec)
      field.split(',').flat_map { |segment| lint_segment(segment, spec) }
    end
    private_class_method :lint_field

    def lint_segment(segment, spec)
      return [] if segment == '*'

      if (star_step_matches = segment.match(%r{\A\*/(\d+)\z}))
        step = star_step_matches[1].to_i
        return lint_step_only(step, spec)
      end

      if (range_matches = segment.match(%r{\A([^/-]+)-([^/]+)(?:/(\d+))?\z}))
        range_start = range_matches[1]
        range_end = range_matches[2]
        step_token = range_matches[3]
        start = parse_value(range_start, spec)
        ending = parse_value(range_end, spec)
        step = step_token&.to_i
        return lint_range_segment(segment, start, ending, step, spec)
      end

      if (base_step_matches = segment.match(%r{\A([^/]+)/(\d+)\z}))
        base_token = base_step_matches[1]
        step_token = base_step_matches[2]
        base = parse_value(base_token, spec)
        step = step_token.to_i
        return lint_base_step_segment(segment, base, step, spec)
      end

      value = parse_value(segment, spec)
      return ["#{spec[:name]} value '#{segment}' is out of range (#{spec[:min]}-#{spec[:max]})."] unless value

      []
    end
    private_class_method :lint_segment

    def lint_step_only(step, spec)
      field_size = spec[:max] - spec[:min] + 1
      return [] if step.between?(1, field_size)

      ["#{spec[:name]} step '#{step}' is out of range. Allowed step: 1-#{field_size}."]
    end
    private_class_method :lint_step_only

    def lint_range_segment(segment, start_value, end_value, step, spec)
      field_name = spec[:name]
      return ["#{field_name} range '#{segment}' contains an out-of-range value."] unless start_value && end_value
      return ["#{field_name} range '#{segment}' has start greater than end."] if start_value > end_value
      return [] unless step

      span = end_value - start_value + 1
      return [] if step.between?(1, span)

      ["#{field_name} step '#{step}' is out of range for range '#{segment}'. Allowed step: 1-#{span}."]
    end
    private_class_method :lint_range_segment

    def lint_base_step_segment(segment, base, step, spec)
      field_name = spec[:name]
      return ["#{field_name} value '#{segment}' contains an out-of-range value."] unless base
      return [] if step.positive?

      ["#{field_name} step '#{step}' is out of range. Allowed step: 1 or greater."]
    end
    private_class_method :lint_base_step_segment

    def parse_value(token, spec)
      names = spec[:names]
      token_key = token.downcase
      return names[token_key] if names&.key?(token_key)
      return nil unless token.match?(/\A\d+\z/)

      value = token.to_i
      return nil unless value.between?(spec[:min], spec[:max])

      value
    end
    private_class_method :parse_value

    def normalize(expression)
      expression.to_s.strip.gsub(/\s+/, ' ')
    end
    private_class_method :normalize

    def safe_normalize(expression)
      normalize(expression)
    rescue StandardError
      nil
    end
    private_class_method :safe_normalize

    def macro?(expression)
      expression.start_with?('@')
    end
    private_class_method :macro?

    def five_fields?(expression)
      expression.split.length == 5
    end
    private_class_method :five_fields?

    def canonical_macro_for(macro)
      CANONICAL_MACROS.fetch(MACRO_MAP[macro], macro)
    end
    private_class_method :canonical_macro_for

    def unsupported_macro_message(expression)
      supported = MACRO_MAP.keys.sort.join(', ')
      "Unsupported cron macro '#{expression}'. Supported macros: #{supported}."
    end
    private_class_method :unsupported_macro_message

    def field_count_message(expression)
      "Invalid cron expression '#{expression}'. Expected 5 fields: minute hour day-of-month month day-of-week."
    end
    private_class_method :field_count_message

    def invalid_expression_message(expression)
      shown = expression.empty? ? '<empty>' : expression
      "Invalid cron expression '#{shown}'. Examples: '*/5 * * * *', '@daily'."
    end
    private_class_method :invalid_expression_message
  end
end
