# frozen_string_literal: true

# Every table in db/schema.rb becomes a model in RolesDB. has_many_through adds
# Role#permissions through role_permissions. user_roles.user_id and organization_id refer
# to the auth service, so they have no associations here.
DynamicActiveModel::Rails.configure do |config|
  config.add_database :roles, foreign_key_constraints: true, has_many_through: true
end
