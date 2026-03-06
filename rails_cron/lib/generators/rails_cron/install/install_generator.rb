# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module RailsCron
  module Generators
    # Installs the database migrations needed for the selected backend.
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      class_option :backend,
                   type: :string,
                   default: 'sqlite',
                   desc: 'Backend to install migrations for: sqlite, postgres, mysql, redis, memory'

      def create_initializer
        template 'rails_cron.rb.tt', 'config/initializers/rails_cron.rb'
      end

      def create_scheduler_config
        template 'scheduler.yml.tt', 'config/scheduler.yml'
      end

      def install_migrations
        templates = migration_templates
        return say_status(:skip, "No database migrations required for #{normalized_backend} backend", :yellow) if templates.empty?

        templates.each do |template_name|
          migration_template "#{template_name}.rb.tt", "db/migrate/#{template_name}.rb"
        end
      end

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      private

      def migration_templates
        case normalized_backend
        when 'sqlite', 'database'
          %w[
            create_rails_cron_dispatches
            create_rails_cron_locks
            create_rails_cron_definitions
          ]
        when 'postgres', 'mysql'
          %w[
            create_rails_cron_dispatches
            create_rails_cron_definitions
          ]
        when 'memory', 'redis'
          []
        else
          raise Thor::Error, "Unsupported backend '#{options['backend']}'. Use sqlite, postgres, mysql, redis, or memory."
        end
      end

      def normalized_backend
        options['backend'].to_s.downcase
      end
    end
  end
end
