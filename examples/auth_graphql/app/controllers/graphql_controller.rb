# frozen_string_literal: true

require 'schema_api/graphql'

# POST /graphql, the only API endpoint.
class GraphqlController < ApplicationController
  include SchemaApi::Graphql

  graphql_resources Resources::UsersController, Resources::OrganizationsController, Resources::SessionsController
end
