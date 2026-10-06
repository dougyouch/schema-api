# frozen_string_literal: true

require 'graphql'
require 'schema_api'

module SchemaApi
  # A GraphQL endpoint generated from SchemaApi controllers. Each controller's schema becomes
  # an object type, and its index and show become query fields that run through the
  # controller itself: its before_actions, resource_scope, search, pagination and
  # resource_json. A field can't return anything the REST endpoint wouldn't.
  #
  # Optional: add the graphql gem and require 'schema_api/graphql'.
  #
  #   class GraphqlController < ApplicationController
  #     include SchemaApi::Graphql
  #     graphql_resources UsersController, OrganizationsController
  #   end
  #
  #   post 'graphql', to: 'graphql#execute'
  module Graphql
    autoload :ClassMethods, 'schema_api/graphql/class_methods'
    autoload :ControllerRunner, 'schema_api/graphql/controller_runner'
    autoload :ErrorHandler, 'schema_api/graphql/error_handler'
    autoload :Execution, 'schema_api/graphql/execution'
    autoload :FilterTypeBuilder, 'schema_api/graphql/filter_type_builder'
    autoload :PageMetaType, 'schema_api/graphql/page_meta_type'
    autoload :RequestParser, 'schema_api/graphql/request_parser'
    autoload :ResourceFields, 'schema_api/graphql/resource_fields'
    autoload :ScalarTypes, 'schema_api/graphql/scalar_types'
    autoload :SchemaBuilder, 'schema_api/graphql/schema_builder'
    autoload :TypeBuilder, 'schema_api/graphql/type_builder'

    # @api private
    def self.included(base)
      base.include SchemaApi unless base < SchemaApi
      base.extend ClassMethods
      base.include Execution
    end
  end
end
