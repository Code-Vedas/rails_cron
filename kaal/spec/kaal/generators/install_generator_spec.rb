# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'rails/generators'
require 'generators/kaal/install/install_generator'

RSpec.describe Kaal::Generators::InstallGenerator do
  let(:destination_root) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(destination_root)
  end

  def build_generator(backend:)
    described_class.new([], { 'backend' => backend }, destination_root:)
  end

  describe '.next_migration_number' do
    it 'delegates to ActiveRecord generator numbering' do
      allow(ActiveRecord::Generators::Base).to receive(:next_migration_number).with('db/migrate').and_return('20260303001000')

      result = described_class.next_migration_number('db/migrate')

      expect(result).to eq('20260303001000')
    end
  end

  describe '#install_migrations' do
    it 'copies sqlite migrations' do
      generator = build_generator(backend: 'sqlite')
      allow(generator).to receive(:migration_template)

      generator.install_migrations

      expect(generator).to have_received(:migration_template).with(
        'create_kaal_dispatches.rb.tt',
        'db/migrate/create_kaal_dispatches.rb'
      )
      expect(generator).to have_received(:migration_template).with(
        'create_kaal_locks.rb.tt',
        'db/migrate/create_kaal_locks.rb'
      )
      expect(generator).to have_received(:migration_template).with(
        'create_kaal_definitions.rb.tt',
        'db/migrate/create_kaal_definitions.rb'
      )
    end

    it 'copies postgres migrations without lock table' do
      generator = build_generator(backend: 'postgres')
      allow(generator).to receive(:migration_template)

      generator.install_migrations

      expect(generator).to have_received(:migration_template).with(
        'create_kaal_dispatches.rb.tt',
        'db/migrate/create_kaal_dispatches.rb'
      )
      expect(generator).to have_received(:migration_template).with(
        'create_kaal_definitions.rb.tt',
        'db/migrate/create_kaal_definitions.rb'
      )
      expect(generator).not_to have_received(:migration_template).with(
        'create_kaal_locks.rb.tt',
        'db/migrate/create_kaal_locks.rb'
      )
    end

    it 'skips migrations for redis backend' do
      generator = build_generator(backend: 'redis')
      allow(generator).to receive(:migration_template)
      allow(generator).to receive(:say_status)

      generator.install_migrations

      expect(generator).not_to have_received(:migration_template)
      expect(generator).to have_received(:say_status).with(
        :skip,
        'No database migrations required for redis backend',
        :yellow
      )
    end

    it 'raises for unsupported backends' do
      generator = build_generator(backend: 'unknown')

      expect { generator.install_migrations }.to raise_error(Thor::Error, /Unsupported backend/)
    end
  end

  describe '#create_initializer' do
    it 'creates the Kaal initializer' do
      generator = build_generator(backend: 'sqlite')
      allow(generator).to receive(:template)

      generator.create_initializer

      expect(generator).to have_received(:template).with(
        'kaal.rb.tt',
        'config/initializers/kaal.rb'
      )
    end
  end

  describe '#create_scheduler_config' do
    it 'creates the default scheduler YAML file' do
      generator = build_generator(backend: 'sqlite')
      allow(generator).to receive(:template)

      generator.create_scheduler_config

      expect(generator).to have_received(:template).with(
        'scheduler.yml.tt',
        'config/scheduler.yml'
      )
    end
  end
end
