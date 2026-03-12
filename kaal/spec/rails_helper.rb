# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'simplecov'
require 'active_support/testing/time_helpers'

unless ENV['NO_COVERAGE'] == '1'
  SimpleCov.start do
    track_files '{app,lib,spec}/**/*.rb'
    add_filter '/spec/'
    add_filter %r{^/lib/.*/version\.rb$}

    enable_coverage :branch
    minimum_coverage 100
  end
end

# Shell-escaped passwords are often passed as `\!` in DATABASE_URL. Normalize that
# before Rails boots so Active Record can parse the URL.
ENV['DATABASE_URL'] = ENV['DATABASE_URL'].gsub('\!', '!') if ENV['DATABASE_URL']

require 'rails'
ENV['RAILS_ENV'] ||= 'test'
abort('The Rails environment is running in production mode!') if Rails.env.production?
require File.expand_path('dummy/config/environment', __dir__) if File.exist?(File.expand_path(
                                                                               'dummy/config/environment.rb', __dir__
                                                                             ))
require 'kaal'
require 'rspec/rails'
Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  config.include ActiveJob::TestHelper
  config.include ActiveSupport::Testing::TimeHelpers

  config.use_transactional_fixtures = false
  config.fixture_paths = [Rails.root.join('spec/fixtures')]
  config.filter_rails_from_backtrace!

  config.before do
    Kaal::CronDispatch.delete_all
    Kaal::CronDefinition.delete_all if defined?(Kaal::CronDefinition)
  end

  config.after do
    travel_back
  rescue RuntimeError => e
    raise unless e.message.to_s.include?('travel back')
  end

  config.after do
    coordinator = Kaal.instance_variable_get(:@coordinator)
    coordinator&.stop! if coordinator.respond_to?(:stop!)

    Kaal.instance_variable_set(:@coordinator, nil)
    Kaal.instance_variable_set(:@registry, Kaal::Registry.new)
    Kaal.instance_variable_set(:@configuration, Kaal::Configuration.new)
    Kaal.instance_variable_set(:@definition_registry, nil)
  rescue StandardError
    # Test cleanup should not mask the original failure.
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
