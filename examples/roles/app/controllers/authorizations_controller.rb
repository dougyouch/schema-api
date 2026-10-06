# frozen_string_literal: true

# GET /authorize?organization_id=1&user_id=2&resource=cars&action=write
#
# Not a resource, but SchemaApi.parse! parses its query with a schema and raises in the same
# error format as every SchemaApi endpoint.
class AuthorizationsController < ApplicationController
  def show
    query = SchemaApi.parse!(AuthorizationQuery, request.query_parameters)
    roles = granting_roles(query)
    render json: { authorization: query.as_json.merge(allowed: roles.any?, roles: roles.map(&:name)) }
  end

  private

  def granting_roles(query)
    user_roles = RolesDB::UserRole.where(organization_id: query.organization_id, user_id: query.user_id)
    granting = RolesDB::RolePermission.joins(:permission)
                                      .where(permissions: { resource: query.resource, action: query.action })
    RolesDB::Role.where(id: user_roles.select(:role_id)).where(id: granting.select(:role_id)).order(:name)
  end
end
