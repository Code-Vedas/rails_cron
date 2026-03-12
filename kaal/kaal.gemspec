# frozen_string_literal: true

require_relative 'lib/kaal/version'

Gem::Specification.new do |spec|
  spec.name        = 'kaal'
  spec.version     = Kaal::VERSION
  spec.authors = ['Nitesh Purohit']
  spec.email = ['nitesh.purohit.it@gmail.com']
  spec.summary       = 'Distributed cron scheduler for Ruby.'
  spec.description   = <<-DESC
    Kaal is a distributed cron scheduler for Ruby that safely executes scheduled tasks across multiple nodes.
  DESC
  spec.homepage      = 'https://github.com/Code-Vedas/kaal'
  spec.license       = 'MIT'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/Code-Vedas/kaal/issues'
  spec.metadata['changelog_uri'] = 'https://github.com/Code-Vedas/kaal/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri'] = 'https://kaal.codevedas.com'
  spec.metadata['homepage_uri'] = 'https://github.com/Code-Vedas/kaal'
  spec.metadata['source_code_uri'] = 'https://github.com/Code-Vedas/kaal.git'
  spec.metadata['funding_uri'] = 'https://github.com/sponsors/Code-Vedas'
  spec.metadata['support_uri'] = 'https://kaal.codevedas.com/support'
  spec.metadata['rubygems_uri'] = 'https://rubygems.org/gems/kaal'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,config,db,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end

  spec.add_dependency 'fugit', '~> 1.8'
  spec.add_dependency 'rails', '>= 7.1', '< 9.0'
  spec.add_dependency 'rails-i18n', '>= 7.0'
  spec.required_ruby_version = '>= 3.2'
end
