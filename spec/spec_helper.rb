# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  skip '/spec/'
  enable_coverage :branch
end

require 'rack/test'
require 'schema-api'
require 'schema_api/graphql'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Migration.verbose = false

%w[db models controllers graphql routes request_helpers].each { |file| require_relative "support/#{file}" }

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request
  config.include RequestHelpers, type: :request
  config.define_derived_metadata(file_path: %r{/spec/requests/}) { |metadata| metadata[:type] = :request }

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end

  config.order = :random
  config.disable_monkey_patching!
end
