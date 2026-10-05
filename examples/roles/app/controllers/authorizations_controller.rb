# frozen_string_literal: true

# GET /authorize?organization_id=1&user_id=2&resource=cars&action=write
#
# Not a resource, but it parses its input with a schema and reports problems in the same
# error format as every SchemaApi endpoint.
class AuthorizationsController < ApplicationController
  rescue_from SchemaApi::Error do |error|
    render json: SchemaApi::ErrorSchema.from_error(error).to_response, status: error.status
  end

  def show
    query = parse_query!
    roles = granting_roles(query)
    render json: { authorization: query.as_json.merge(allowed: roles.any?, roles: roles.map(&:name)) }
  end

  private

  def parse_query!
    query = AuthorizationQuery.from_hash(request.query_parameters)
    return query if query.parsed_and_valid?

    details = SchemaApi::ErrorCollector.new.parsing_details(query) +
              SchemaApi::ErrorCollector.new.validation_details(query, nil)
    error_class = query.parsed? ? SchemaApi::ValidationError : SchemaApi::InvalidData
    raise error_class.new('Authorization query is invalid', details: details)
  end

  def granting_roles(query)
    user_roles = RolesDB::UserRole.where(organization_id: query.organization_id, user_id: query.user_id)
    granting = RolesDB::RolePermission.joins(:permission)
                                      .where(permissions: { resource: query.resource, action: query.action })
    RolesDB::Role.where(id: user_roles.select(:role_id)).where(id: granting.select(:role_id)).order(:name)
  end
end
