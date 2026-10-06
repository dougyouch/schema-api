# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'

Bundler.require(*Rails.groups)

module AuthGraphql
  # The auth example's users, organizations and sessions, served only as GraphQL.
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.autoload_lib(ignore: %w[tasks])
  end
end
