# frozen_string_literal: true

# GET /organizations/:organization_id/users/:user_id/permissions: everything a user may do
# in an organization, through all of their roles. A read-only SchemaApi resource over a query.
class UserPermissionsController < ApplicationController
  include SchemaApi

  schema(model: 'RolesDB::Permission', root: :permission, collection_root: :permissions, actions: %i[index]) do
    model_attribute :id
    model_attribute :name
    model_attribute :resource
    model_attribute :action
  end

  search do
    filter :resource, op: %i[eq in]
    filter :action, op: %i[eq in]
    sort :resource, :action, default: 'resource,action'
  end

  paginate :offset, limit: { default: 200, max: 1000 }, count: true

  private

  def resource_scope
    RolesDB::Permission.granted_to(organization_id: params[:organization_id], user_id: params[:user_id])
  end
end
