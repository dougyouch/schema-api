# frozen_string_literal: true

module SchemaApi
  module Graphql
    # One controller as GraphQL sees it: its finalized definition, its type name and object
    # type, and which actions it has.
    class Resource
      # @return [Class]
      attr_reader :controller_class
      # @return [Definition]
      attr_reader :definition
      # @return [String] e.g. "User"
      attr_reader :type_name
      # @return [Class] the GraphQL object type
      attr_reader :object_type

      # @param controller_class [Class] a SchemaApi controller
      # @param types [TypeBuilder]
      # @raise [DefinitionError] when the controller has no schema or is nested under a route
      def initialize(controller_class, types)
        @controller_class = controller_class
        @definition = finalized_definition
        @type_name = @definition.root.to_s.camelize
        @object_type = types.object_type(@definition.schema_class, @type_name)
      end

      # @param action [String] e.g. "index"
      # @return [Boolean] whether the controller has the action
      def action?(action)
        controller_class.action_methods.include?(action)
      end

      # @param context [GraphQL::Query::Context]
      # @return [ControllerRunner]
      def runner(context)
        ControllerRunner.new(controller_class, context[:request])
      end

      private

      def finalized_definition
        definition = controller_class.schema_api_definition
        raise DefinitionError, "#{controller_class.name} has no SchemaApi schema" unless definition&.schema_class
        raise DefinitionError, "#{controller_class.name}: nested resources aren't supported by GraphQL yet" if definition.parent

        definition.finalize!
      end
    end
  end
end
