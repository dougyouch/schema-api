# frozen_string_literal: true

# The permission catalog. Each service registers what it checks with one bulk_upsert,
# matched by resource and action:
#
#   PUT /permissions/bulk_upsert
#   { "permissions": [{ "resource": "cars", "action": "write", "name": "Edit cars" }, ...] }
class PermissionsController < ApplicationController
  include SchemaApi

  before_action :require_acting_user!, except: %i[index show]

  schema(model: 'RolesDB::Permission') do
    model_attribute :id
    model_attribute :name, input: true
    model_attribute :description, input: true
    model_attribute :resource, input: :create
    model_attribute :action, input: :create
    model_attribute :created_at
    model_attribute :updated_at

    validates :name, presence: true
    validates :resource, :action, presence: true, format: { with: /\A[a-z][a-z0-9_]*\z/, message: 'must be snake_case' }
  end

  search do
    filter :resource, op: %i[eq in]
    filter :action, op: %i[eq in]
    filter :name, op: :contains
    sort :resource, :action, :name, default: 'resource,action'
  end

  paginate :offset, limit: { default: 100, max: 500 }, count: true
  upsert_key :resource, :action
  bulk max: 500

  private

  def destroy_resource!(permission)
    permission.transaction do
      permission.role_permissions.delete_all
      permission.destroy!
    end
  end
end
