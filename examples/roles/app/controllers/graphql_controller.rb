# frozen_string_literal: true

require 'schema_api/graphql'

# POST /graphql: roles, permissions and user roles as GraphQL queries and mutations. Reads
# are open to callers inside the network and writes need X-User-Id, as over REST.
class GraphqlController < ApplicationController
  include SchemaApi::Graphql

  graphql_resources RolesController, PermissionsController, UserRolesController
end
