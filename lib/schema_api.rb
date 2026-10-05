# frozen_string_literal: true

require 'json'
require 'time'
require 'base64'
require 'active_record'
require 'action_controller'
require 'schema-model'
require 'model-mapper'

# SchemaApi turns a Rails controller into a resource API declared as an inline schema.
#
#   class CarsController < ApplicationController
#     include SchemaApi
#
#     schema do
#       model_attribute :id
#       model_attribute :make, input: true
#     end
#   end
module SchemaApi
  autoload :BulkConfig, 'schema_api/bulk_config'
  autoload :BulkResult, 'schema_api/bulk_result'
  autoload :CallbackChain, 'schema_api/callback_chain'
  autoload :ChildMatcher, 'schema_api/child_matcher'
  autoload :ClassMethods, 'schema_api/class_methods'
  autoload :CreateOnlyCheck, 'schema_api/create_only_check'
  autoload :Definition, 'schema_api/definition'
  autoload :ErrorCollector, 'schema_api/error_collector'
  autoload :ErrorList, 'schema_api/error_list'
  autoload :ErrorSchema, 'schema_api/error_schema'
  autoload :Field, 'schema_api/field'
  autoload :IncludesBuilder, 'schema_api/includes_builder'
  autoload :InputChecker, 'schema_api/input_checker'
  autoload :InputParser, 'schema_api/input_parser'
  autoload :Lookup, 'schema_api/lookup'
  autoload :MappingBuilder, 'schema_api/mapping_builder'
  autoload :ModelErrors, 'schema_api/model_errors'
  autoload :Naming, 'schema_api/naming'
  autoload :ParentConfig, 'schema_api/parent_config'
  autoload :ParentLookup, 'schema_api/parent_lookup'
  autoload :PatchMerger, 'schema_api/patch_merger'
  autoload :Persistence, 'schema_api/persistence'
  autoload :Presenter, 'schema_api/presenter'
  autoload :Rendering, 'schema_api/rendering'
  autoload :ResourceSchema, 'schema_api/resource_schema'
  autoload :Routing, 'schema_api/routing'
  autoload :SchemaClassBuilder, 'schema_api/schema_class_builder'
  autoload :SchemaFinalizer, 'schema_api/schema_finalizer'
  autoload :SchemaParser, 'schema_api/schema_parser'
  autoload :Serializer, 'schema_api/serializer'
  autoload :TimeFormatter, 'schema_api/time_formatter'
  autoload :TreeChanges, 'schema_api/tree_changes'
  autoload :TreeExecutor, 'schema_api/tree_executor'
  autoload :TreeNode, 'schema_api/tree_node'
  autoload :TreePlanner, 'schema_api/tree_planner'
  autoload :TypeResolver, 'schema_api/type_resolver'
  autoload :ValueComparer, 'schema_api/value_comparer'
  autoload :VERSION, 'schema_api/version'
  autoload :WriteContext, 'schema_api/write_context'

  # Controller actions
  module Actions
    autoload :Bulk, 'schema_api/actions/bulk'
    autoload :Crud, 'schema_api/actions/crud'
    autoload :Search, 'schema_api/actions/search'
    autoload :Upsert, 'schema_api/actions/upsert'
  end

  # index filtering and sorting
  module Search
    autoload :Definition, 'schema_api/search/definition'
    autoload :Filter, 'schema_api/search/filter'
    autoload :ParamsParser, 'schema_api/search/params_parser'
    autoload :Query, 'schema_api/search/query'
    autoload :Sort, 'schema_api/search/sort'
  end

  # cursor and offset pagination
  module Pagination
    autoload :Config, 'schema_api/pagination/config'
    autoload :Cursor, 'schema_api/pagination/cursor'
    autoload :Offset, 'schema_api/pagination/offset'
    autoload :Page, 'schema_api/pagination/page'
  end

  # Adds the macros and error handling to a controller. Actions are added by `schema`, so
  # SchemaApi can be included once in ApplicationController.
  # @api private
  def self.included(base)
    base.extend ClassMethods
    base.include Lookup, ParentLookup, Rendering, Persistence
    base.rescue_from Error, with: :render_error
    base.rescue_from ActiveRecord::RecordNotFound, with: :render_record_not_found
  end

  # Parses data with a schema-model schema, raising {InvalidData} or {ValidationError} with
  # SchemaApi's error details. See {SchemaParser}.
  # @return [Schema::Model]
  def self.parse!(schema_class, data, context: nil)
    SchemaParser.new(schema_class).parse!(data, context: context)
  end

  # Controllers that declared a schema.
  # @return [Array<Class>]
  def self.controllers
    @controllers ||= []
  end

  # @api private
  def self.register(controller)
    controllers << controller unless controllers.include?(controller)
  end

  # Finalizes every controller's schema, e.g. from an initializer or a spec, so a mistyped
  # column fails at boot instead of on the first request.
  # @return [void]
  def self.finalize_all!
    controllers.each { |controller| controller.schema_api_definition.finalize! }
  end
end

require 'schema_api/errors'
ActionDispatch::Routing::Mapper.include(SchemaApi::Routing)
