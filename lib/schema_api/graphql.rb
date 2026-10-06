# frozen_string_literal: true

require 'graphql'
require 'schema_api'

module SchemaApi
  # A GraphQL endpoint generated from SchemaApi controllers. Each controller's schema becomes
  # an object type and an input type; index and show become query fields, and create, update,
  # upsert and destroy become mutations. Every field runs through the controller itself: its
  # before_actions, resource_scope, search, write pipeline and resource_json, so GraphQL
  # can't read or write anything the REST endpoint wouldn't.
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
    autoload :InputTypeBuilder, 'schema_api/graphql/input_type_builder'
    autoload :MutationFields, 'schema_api/graphql/mutation_fields'
    autoload :PageMetaType, 'schema_api/graphql/page_meta_type'
    autoload :QueryFields, 'schema_api/graphql/query_fields'
    autoload :RequestParser, 'schema_api/graphql/request_parser'
    autoload :Resource, 'schema_api/graphql/resource'
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
