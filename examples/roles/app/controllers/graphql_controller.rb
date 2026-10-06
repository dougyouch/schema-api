# frozen_string_literal: true

require 'schema_api/graphql'

# POST /graphql: roles, permissions and user roles as GraphQL queries. Reads are open to
# callers inside the network, as they are over REST.
class GraphqlController < ApplicationController
  include SchemaApi::Graphql

  graphql_resources RolesController, PermissionsController, UserRolesController
end
