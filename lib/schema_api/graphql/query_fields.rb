# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Adds one resource's query fields: a list named after its collection root, for index,
    # and a single-record field named after its root, for show.
    #
    #   users(filter: UserFilter, sort: String, limit: Int, cursor: String): UserList
    #   user(id: ID!): User
    class QueryFields
      # @param resource [Resource]
      def initialize(resource)
        @resource = resource
        @definition = resource.definition
      end

      # @param query_type [Class] the Query type
      # @return [void]
      def add_to(query_type)
        add_list_field(query_type) if @resource.action?('index')
        add_find_field(query_type) if @resource.action?('show')
      end

      private

      def add_list_field(query_type)
        name = @definition.collection_root.to_s
        filters = FilterTypeBuilder.new(@definition.search, @resource.type_name)
        field = query_type.field(name, list_type, null: true, camelize: false, resolver_method: :"resolve_#{name}")
        field.argument(:filter, filters.build, required: false, camelize: false) if filters.filters?
        add_page_arguments(field)
        define_list_resolver(query_type, name, filters)
      end

      def add_page_arguments(field)
        @definition.pagination.param_types.each do |param, type|
          field.argument(param, ScalarTypes.value_type(type), required: false, camelize: false)
        end
      end

      def define_list_resolver(query_type, name, filters)
        resource = @resource
        query_type.define_method(:"resolve_#{name}") do |filter: nil, **page|
          resource.runner(context).list(filters.to_params(filter).merge(page.transform_keys(&:to_s)))
        end
      end

      def add_find_field(query_type)
        name = @definition.root.to_s
        resource = @resource
        query_type.field(name, resource.object_type, null: true, camelize: false, resolver_method: :"resolve_#{name}") do
          argument :id, ::GraphQL::Types::ID, required: true
        end
        query_type.define_method(:"resolve_#{name}") { |id:| resource.runner(context).find(id) }
      end

      def list_type
        type = Class.new(::GraphQL::Schema::Object)
        type.graphql_name("#{@resource.type_name}List")
        type.field(:nodes, [@resource.object_type], null: false, hash_key: :nodes)
        type.field(:meta, PageMetaType, null: false, hash_key: :meta)
        type
      end
    end
  end
end
