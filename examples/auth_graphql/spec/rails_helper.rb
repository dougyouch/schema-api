# frozen_string_literal: true

# the shell may export RAILS_ENV=development; specs always run in test
ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment'
require 'rspec/rails'

ActiveRecord::Migration.maintain_test_schema!
Dir[Rails.root.join('spec/support/**/*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.include AuthGraphqlHelpers, type: :request
  config.include ActiveSupport::Testing::TimeHelpers
  config.order = :random
  config.disable_monkey_patching!
end
