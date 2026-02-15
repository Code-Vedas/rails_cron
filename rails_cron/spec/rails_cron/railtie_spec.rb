# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe RailsCron::Railtie do
  before do
    RailsCron.reset_configuration!
  end

  describe '.ensure_logger!' do
    it 'sets configuration logger when Rails.logger is present' do
      test_logger = Logger.new(StringIO.new)
      allow(Rails).to receive(:logger).and_return(test_logger)

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be(test_logger)
    end

    it 'does not override an existing configuration logger' do
      existing_logger = Logger.new(StringIO.new)
      RailsCron.configuration.logger = existing_logger

      allow(Rails).to receive(:logger).and_return(Logger.new(StringIO.new))

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be(existing_logger)
    end

    it 'does nothing when Rails.logger is nil' do
      allow(Rails).to receive(:logger).and_return(nil)

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be_nil
    end

    it 'does nothing when Rails.logger raises NoMethodError' do
      allow(Rails).to receive(:logger).and_raise(NoMethodError)

      described_class.ensure_logger!

      expect(RailsCron.configuration.logger).to be_nil
    end
  end
end
