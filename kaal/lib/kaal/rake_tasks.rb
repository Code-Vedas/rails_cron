# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'rake'

module Kaal
  ##
  # Defines Kaal rake tasks on a given Rake application.
  module RakeTasks
    SIGNALS = %w[TERM INT].freeze
    SHUTDOWN_TIMEOUT = 30
    RESERVED_SIGNAL_HANDLERS = %w[DEFAULT IGNORE SYSTEM_DEFAULT EXIT].freeze

    module_function

    def install(rake_application = Rake.application)
      rake_application.extend(Rake::DSL)

      rake_application.instance_eval do
        namespace :kaal do
          Kaal::RakeTasks.define_tick_task(self)
          Kaal::RakeTasks.define_status_task(self)
          Kaal::RakeTasks.define_explain_task(self)
          Kaal::RakeTasks.define_start_task(self)
        end
      end
    end

    def define_tick_task(context)
      context.instance_eval do
        desc 'Perform a single scheduler tick'
        task tick: :environment do
          Kaal.tick!
          puts 'Kaal tick completed'
        rescue StandardError => e
          abort("kaal:tick failed: #{e.message}")
        end
      end
    end

    def define_status_task(context)
      context.instance_eval do
        desc 'Show scheduler status, configuration, and registered cron jobs'
        task status: :environment do
          puts "Kaal v#{Kaal::VERSION}"
          puts "Running: #{Kaal.running?}"
          puts "Tick interval: #{Kaal.tick_interval}s"
          puts "Window lookback: #{Kaal.window_lookback}s"
          puts "Window lookahead: #{Kaal.window_lookahead}s"
          puts "Lease TTL: #{Kaal.lease_ttl}s"
          puts "Namespace: #{Kaal.namespace}"

          entries = Kaal.registered
          puts "Registered jobs: #{entries.length}"
          entries.each do |entry|
            puts "  - #{entry.key} (#{entry.cron})"
          end
        rescue StandardError => e
          abort("kaal:status failed: #{e.message}")
        end
      end
    end

    def define_explain_task(context)
      context.instance_eval do
        desc 'Humanize a cron expression, e.g. rake kaal:explain["*/5 * * * *"]'
        task :explain, [:expr] => :environment do |_task, args|
          expression = args[:expr].to_s.strip
          abort('kaal:explain requires expr argument') if expression.empty?

          puts Kaal.to_human(expression)
        rescue StandardError => e
          abort("kaal:explain failed: #{e.message}")
        end
      end
    end

    def define_start_task(context)
      context.instance_eval do
        desc 'Start scheduler loop in foreground (blocks until stopped)'
        task start: :environment do
          signal_state = {
            graceful_shutdown_started: false,
            shutdown_complete: false,
            force_exit_requested: false
          }
          previous_handlers = Kaal::RakeTasks.install_foreground_signal_handlers(signal_state)

          begin
            thread = Kaal.start!
            abort('kaal:start failed: scheduler is already running') unless thread

            puts 'Kaal scheduler started in foreground'
            thread.join
          ensure
            Kaal::RakeTasks.restore_signal_handlers(previous_handlers)
          end
        rescue Interrupt
          abort('kaal:start failed: shutdown timed out; forced exit requested') if signal_state[:force_exit_requested]

          Kaal::RakeTasks.shutdown_scheduler(signal: 'INT', signal_state: signal_state)
        rescue StandardError => e
          abort("kaal:start failed: #{e.message}")
        end
      end
    end

    def install_foreground_signal_handlers(signal_state)
      SIGNALS.each_with_object({}) do |signal, handlers|
        previous_handler = capture_previous_signal_handler(signal)
        Signal.trap(signal) do
          shutdown_scheduler(signal: signal, signal_state: signal_state, previous_handler: previous_handler)
        end
        handlers[signal] = previous_handler
      end
    end

    def capture_previous_signal_handler(signal)
      previous_handler = Signal.trap(signal, 'IGNORE')
      Signal.trap(signal, previous_handler)
      previous_handler
    end

    def restore_signal_handlers(previous_handlers)
      previous_handlers.each do |signal, handler|
        Signal.trap(signal, handler)
      rescue StandardError
        nil
      end
    end

    def shutdown_scheduler(signal:, signal_state:, previous_handler: nil)
      return if signal_state[:shutdown_complete]

      if signal_state[:graceful_shutdown_started]
        signal_state[:force_exit_requested] = true
        warn("Received #{signal} again; forcing scheduler shutdown")
        Thread.main.raise(Interrupt)
        return
      end

      signal_state[:graceful_shutdown_started] = true
      puts "Received #{signal}, stopping Kaal scheduler..."
      stopped = Kaal.stop!(timeout: SHUTDOWN_TIMEOUT)
      if stopped
        signal_state[:shutdown_complete] = true
        puts 'Kaal scheduler stopped'
      else
        warn('Kaal scheduler stop timed out; send TERM/INT again to force exit')
      end
    rescue StandardError => e
      warn("kaal:start shutdown failed: #{e.message}")
    ensure
      chain_previous_handler(signal, previous_handler)
    end

    def chain_previous_handler(signal, previous_handler)
      return unless previous_handler

      case previous_handler
      when Proc, Method
        invoke_previous_handler(previous_handler, signal)
      when String
        return if RESERVED_SIGNAL_HANDLERS.include?(previous_handler)

        warn("kaal:start previous #{signal} handler is a command: #{previous_handler}")
      end
    rescue StandardError
      nil
    end

    def invoke_previous_handler(handler, signal)
      signal_number = Signal.list[signal]
      callable_arity = handler.arity
      return handler.call if callable_arity.zero?

      handler.call(signal_number)
    end
  end
end
