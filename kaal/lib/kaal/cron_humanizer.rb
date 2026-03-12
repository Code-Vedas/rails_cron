# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'fugit'
require 'i18n'

module Kaal
  ##
  # Human-friendly cron phrase generation with i18n support.
  module CronHumanizer
    MACRO_PHRASES = {
      '@yearly' => 'phrases.yearly',
      '@monthly' => 'phrases.monthly',
      '@weekly' => 'phrases.weekly',
      '@daily' => 'phrases.daily',
      '@hourly' => 'phrases.hourly'
    }.freeze

    module_function

    def to_human(expression, locale: nil)
      normalized = CronUtils.safe_normalize_expression(expression)
      raise ArgumentError, CronUtils.invalid_expression_error_message('') unless normalized
      raise ArgumentError, CronUtils.invalid_expression_error_message(normalized) if normalized.empty?

      resolved_locale = locale || I18n.locale
      I18n.with_locale(resolved_locale) do
        humanized = humanize_expression(normalized)
        return humanized unless humanized.to_s.strip.empty?

        translate_phrase('phrases.cron_expression', expression: normalized)
      end
    end

    def humanize_expression(normalized)
      error_message = CronUtils.invalid_expression_error_message(normalized)
      return humanize_macro(normalized) if macro?(normalized)

      cron = Fugit.parse_cron(normalized)
      return humanize_cron(cron) if cron

      raise ArgumentError, error_message
    end
    private_class_method :humanize_expression

    def humanize_macro(expression)
      macro = expression.downcase
      raise ArgumentError, CronUtils.unsupported_macro_error_message(expression) unless CronUtils::MACRO_MAP.key?(macro)

      canonical_macro = CronUtils::CANONICAL_MACROS.fetch(CronUtils::MACRO_MAP.fetch(macro), macro)
      phrase_key = MACRO_PHRASES.fetch(canonical_macro, nil)
      return translate_phrase(phrase_key) if phrase_key

      translate_phrase('phrases.cron_expression', expression: expression)
    end
    private_class_method :humanize_macro

    def humanize_cron(cron)
      canonical = cron.to_cron_s
      macro = CronUtils::CANONICAL_MACROS[canonical]
      return humanize_macro(macro) if macro

      interval_phrase = every_minute_interval_phrase(cron)
      return interval_phrase if interval_phrase

      weekday_phrase = at_time_weekday_phrase(cron)
      return weekday_phrase if weekday_phrase

      daily_phrase = at_time_daily_phrase(cron)
      return daily_phrase if daily_phrase

      translate_phrase('phrases.cron_expression', expression: canonical)
    end
    private_class_method :humanize_cron

    def every_minute_interval_phrase(cron)
      return nil if cron.hours || cron.monthdays || cron.months || cron.weekdays

      minutes = cron.minutes
      return nil unless minutes.is_a?(Array) && minutes.length > 1

      interval = derive_interval(minutes)
      return nil unless interval

      unit = interval_unit(interval, singular: 'minute', plural: 'minutes')
      translate_phrase('phrases.every_interval', count: interval, unit: unit)
    end
    private_class_method :every_minute_interval_phrase

    def derive_interval(minutes)
      return nil unless minutes.first.zero?

      diffs = minutes.each_cons(2).map { |left, right| right - left }.uniq
      return nil unless diffs.length == 1

      interval = diffs.first
      return nil unless interval.positive?
      return nil unless minutes.last == 60 - interval

      interval
    end
    private_class_method :derive_interval

    def at_time_weekday_phrase(cron)
      return nil unless single_time?(cron)

      weekdays = cron.weekdays
      return nil if cron.monthdays || cron.months || !weekdays

      weekday = extract_weekday(weekdays)
      return nil unless weekday

      time = format_time(cron.hours.first, cron.minutes.first)
      "#{translate_phrase('phrases.at_time', time: time)} #{translate_phrase('every')} #{weekday_name(weekday)}"
    end
    private_class_method :at_time_weekday_phrase

    def at_time_daily_phrase(cron)
      return nil unless single_time?(cron)
      return nil if cron.monthdays || cron.months || cron.weekdays

      time = format_time(cron.hours.first, cron.minutes.first)
      "#{translate_phrase('phrases.at_time', time: time)} #{translate_phrase('every')} #{translate_phrase('time.day')}"
    end
    private_class_method :at_time_daily_phrase

    def single_time?(cron)
      minutes = cron.minutes
      hours = cron.hours

      minutes.is_a?(Array) && minutes.size == 1 &&
        hours.is_a?(Array) && hours.size == 1
    end
    private_class_method :single_time?

    def extract_weekday(weekdays)
      return nil unless weekdays.is_a?(Array) && weekdays.size == 1

      token = weekdays.first
      return token if token.is_a?(Integer)

      if token.is_a?(Array) && token.size == 1
        candidate = token.first
        return candidate if candidate.is_a?(Integer)
      end

      nil
    end
    private_class_method :extract_weekday

    def weekday_name(day)
      normalized_day = day == 7 ? 0 : day
      translate_phrase("weekdays.#{normalized_day}")
    end
    private_class_method :weekday_name

    def format_time(hour, minute)
      format('%<hour>02d:%<minute>02d', hour: hour, minute: minute)
    end
    private_class_method :format_time

    def interval_unit(count, singular:, plural:)
      key = count == 1 ? singular : plural
      translate_phrase("time.#{key}")
    end
    private_class_method :interval_unit

    def macro?(expression)
      expression.start_with?('@')
    end
    private_class_method :macro?

    def translate_phrase(key, **)
      I18n.t("kaal.#{key}", **)
    end
    private_class_method :translate_phrase
  end
end
