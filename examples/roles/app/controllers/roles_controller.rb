# frozen_string_literal: true

# Roles and the permissions they grant. permission_ids is written as a plain list of ids
# (stored as role_permissions rows); permissions renders the full objects.
class RolesController < ApplicationController
  before_action :require_acting_user!, except: %i[index show]

  schema(model: 'RolesDB::Role') do
    model_attribute :id
    model_attributes :name, :description, input: true
    attribute :permission_ids, :array, data_type: :integer, input: true,
                                       values_of: { association: :role_permissions, field: :permission_id }
    attribute :permissions, :array, includes: :permissions, value: lambda { |role|
      role.permissions.map { |permission| permission.slice(:id, :name, :resource, :action) }
    }
    timestamps

    validates :name, presence: true, format: { with: /\A[a-z][a-z0-9_]*\z/, message: 'must be snake_case' }
  end

  search do
    filter :name, op: %i[eq contains]
    # ?permission=cars:write finds the roles that grant it
    filter(:permission, :string) do |scope, value|
      resource, action = value.split(':', 2)
      granting = RolesDB::RolePermission.joins(:permission).where(permissions: { resource: resource, action: action })
      scope.where(id: granting.select(:role_id))
    end
    sort :name, :created_at, default: 'name'
  end

  paginate :offset, limit: { default: 50, max: 200 }, count: true
  upsert_key :name
  bulk max: 50

  validate_input :check_permissions_exist

  private

  # the role_permissions rows would fail on a missing permission anyway; this names the bad ids
  def check_permissions_exist(context)
    ids = Array(context.input.permission_ids).compact.uniq
    missing = ids - RolesDB::Permission.where(id: ids).pluck(:id)
    context.errors.add('permission_ids', :not_found, "Permissions #{missing.join(', ')} do not exist") if missing.any?
  end

  # a role still assigned to users can't be deleted
  def destroy_resource!(role)
    if role.user_roles.exists?
      raise SchemaApi::Conflict.new('Role is still assigned to users',
                                    details: [{ field: nil, error: 'in_use', message: 'Remove its user roles first' }])
    end

    role.transaction do
      role.role_permissions.delete_all
      role.destroy!
    end
  end
end
