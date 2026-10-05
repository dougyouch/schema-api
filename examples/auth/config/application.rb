# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'

Bundler.require(*Rails.groups)

module Auth
  # Users, organizations, affiliations, sessions and server-to-server applications.
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.autoload_lib(ignore: %w[tasks])

    # dynamic-active-model's belongs_to are required regardless of column nullability, so
    # required references are validated in the extension files instead
    config.active_record.belongs_to_required_by_default = false
  end
end
