# frozen_string_literal: true

require 'schema_api/graphql'

# POST /graphql: the users, organizations and sessions REST endpoints as GraphQL queries.
# Each field runs its controller's before_actions and resource_scope, so a user token sees
# the same people and organizations it would over REST.
class GraphqlController < ApplicationController
  include SchemaApi::Graphql

  graphql_resources UsersController, OrganizationsController, SessionsController
end
