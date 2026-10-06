# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Builds the GraphQL schema for an endpoint from its controllers.
    class SchemaBuilder
      # @param controllers [Array<Class>] SchemaApi controllers
      # @param max_depth [Integer]
      def initialize(controllers, max_depth:)
        @controllers = controllers
        @max_depth = max_depth
      end

      # @return [Class] a GraphQL::Schema subclass
      # @raise [DefinitionError] when there are no controllers, or one can't be exposed
      def build
        raise DefinitionError, 'graphql_resources: no controllers given' if @controllers.empty?

        query_type, mutation_type = build_root_types
        max_depth = @max_depth
        Class.new(::GraphQL::Schema) do
          query(query_type)
          mutation(mutation_type) if mutation_type.fields.any?
          max_depth(max_depth)
          rescue_from(SchemaApi::Error) { |error, _object, _arguments, context, field| ErrorHandler.new(context).handle(error, field) }
        end
      end

      private

      def build_root_types
        query_type = root_type('Query')
        mutation_type = root_type('Mutation')
        types = TypeBuilder.new
        inputs = InputTypeBuilder.new
        @controllers.each do |controller|
          resource = Resource.new(controller, types)
          QueryFields.new(resource).add_to(query_type)
          MutationFields.new(resource, inputs).add_to(mutation_type)
        end
        [query_type, mutation_type]
      end

      def root_type(name)
        type = Class.new(::GraphQL::Schema::Object)
        type.graphql_name(name)
        type
      end
    end
  end
end
