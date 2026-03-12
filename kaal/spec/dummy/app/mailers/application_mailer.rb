# frozen_string_literal: true

# ApplicationMailer for the dummy app used in testing
class ApplicationMailer < ActionMailer::Base
  default from: 'from@example.com'
  layout 'mailer'
end
