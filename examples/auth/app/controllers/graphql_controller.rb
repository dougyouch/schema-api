# frozen_string_literal: true

require 'schema_api/graphql'

# POST /graphql: the users, organizations and sessions REST endpoints as GraphQL queries and
# mutations. Each field runs its controller's before_actions, resource_scope and write hooks,
# so a token can read and write only what it could over REST.
class GraphqlController < ApplicationController
  include SchemaApi::Graphql

  graphql_resources UsersController, OrganizationsController, SessionsController
end
