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

        query_type = build_query_type
        max_depth = @max_depth
        Class.new(::GraphQL::Schema) do
          query(query_type)
          max_depth(max_depth)
          rescue_from(SchemaApi::Error) { |error, _object, _arguments, context, field| ErrorHandler.new(context).handle(error, field) }
        end
      end

      private

      def build_query_type
        query_type = Class.new(::GraphQL::Schema::Object)
        query_type.graphql_name('Query')
        types = TypeBuilder.new
        @controllers.each { |controller| ResourceFields.new(controller, types).add_to(query_type) }
        query_type
      end
    end
  end
end
