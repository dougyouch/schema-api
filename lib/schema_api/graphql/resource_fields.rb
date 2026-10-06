# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Adds one controller's query fields: a list named after its collection root, for index,
    # and a single-record field named after its root, for show.
    #
    #   users(filter: UserFilter, sort: String, limit: Int, cursor: String): UserList
    #   user(id: ID!): User
    class ResourceFields
      # @param controller_class [Class] a SchemaApi controller
      # @param types [TypeBuilder]
      def initialize(controller_class, types)
        @controller_class = controller_class
        @definition = definition
        @type_name = @definition.root.to_s.camelize
        @object_type = types.object_type(@definition.schema_class, @type_name)
      end

      # @param query_type [Class] the Query type
      # @return [void]
      def add_to(query_type)
        add_list_field(query_type) if action?('index')
        add_find_field(query_type) if action?('show')
      end

      private

      def definition
        definition = @controller_class.schema_api_definition
        raise DefinitionError, "#{@controller_class.name} has no SchemaApi schema" unless definition&.schema_class
        raise DefinitionError, "#{@controller_class.name}: nested resources aren't supported by GraphQL yet" if definition.parent

        definition.finalize!
      end

      def action?(action)
        @controller_class.action_methods.include?(action)
      end

      def add_list_field(query_type)
        name = @definition.collection_root.to_s
        filters = FilterTypeBuilder.new(@definition.search, @type_name)
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
        controller_class = @controller_class
        query_type.define_method(:"resolve_#{name}") do |filter: nil, **page|
          ControllerRunner.new(controller_class, context[:request])
                          .list(filters.to_params(filter).merge(page.transform_keys(&:to_s)))
        end
      end

      def add_find_field(query_type)
        name = @definition.root.to_s
        controller_class = @controller_class
        query_type.field(name, @object_type, null: true, camelize: false, resolver_method: :"resolve_#{name}") do
          argument :id, ::GraphQL::Types::ID, required: true
        end
        query_type.define_method(:"resolve_#{name}") do |id:|
          ControllerRunner.new(controller_class, context[:request]).find(id)
        end
      end

      def list_type
        object_type = @object_type
        type = Class.new(::GraphQL::Schema::Object)
        type.graphql_name("#{@type_name}List")
        type.field(:nodes, [object_type], null: false, hash_key: :nodes)
        type.field(:meta, PageMetaType, null: false, hash_key: :meta)
        type
      end
    end
  end
end
