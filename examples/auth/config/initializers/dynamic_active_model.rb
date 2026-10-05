# frozen_string_literal: true

# Every table in db/schema.rb becomes a model in AuthDB (AuthDB::User, AuthDB::Session, ...),
# with associations from foreign keys. Extensions are in app/models/auth_db/<table>.ext.rb.
DynamicActiveModel::Rails.configure do |config|
  config.add_database :auth, foreign_key_constraints: true
end
