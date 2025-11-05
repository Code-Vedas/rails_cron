# frozen_string_literal: true

require_relative 'lib/rails_cron/version'

Gem::Specification.new do |spec|
  spec.name        = 'rails_cron'
  spec.version     = RailsCron::VERSION
  spec.authors = ['Nitesh Purohit']
  spec.email = ['nitesh.purohit.it@gmail.com']
  spec.summary       = 'Ruby gem for managing cron jobs in Rails applications.'
  spec.description   = <<-DESC
    Rails Cron is a Ruby gem that simplifies the management of cron jobs in Rails applications, providing an easy-to-use interface for scheduling and monitoring background tasks.
  DESC
  spec.homepage      = 'https://github.com/Code-Vedas/rails_cron'
  spec.license       = 'MIT'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Code-Vedas/rails_cron/issues'
  spec.metadata['changelog_uri'] = 'https://github.com/Code-Vedas/rails_cron/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://rails-cron.codevedas.com'
  spec.metadata['homepage_uri'] = 'https://github.com/Code-Vedas/rails_cron'
  spec.metadata['source_code_uri'] = 'https://github.com/Code-Vedas/rails_cron.git'
  spec.metadata['funding_uri'] = 'https://github.com/sponsors/Code-Vedas'
  spec.metadata['support_uri'] = 'https://rails-cron.codevedas.com/support'
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/rails_cron'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,config,db,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end

  spec.add_dependency 'rails', '>= 7.1', '< 9.0'
  spec.add_dependency 'rails-i18n', '>= 7.0'
  spec.required_ruby_version = '>= 3.2'
end
