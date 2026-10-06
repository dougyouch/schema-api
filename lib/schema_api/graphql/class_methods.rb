# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Macros added to the GraphQL endpoint controller.
    module ClassMethods
      # Default limit on how deeply a query may nest.
      DEFAULT_MAX_DEPTH = 15

      # Declares the SchemaApi controllers the endpoint exposes. Each adds a list field named
      # after its collection root (users) and a single-record field named after its root (user),
      # for the index and show actions it has.
      # @param controllers [Array<Class>]
      # @param max_depth [Integer] deepest query nesting allowed
      # @return [void]
      def graphql_resources(*controllers, max_depth: DEFAULT_MAX_DEPTH)
        @graphql_resources = controllers.flatten
        @graphql_max_depth = max_depth
        @graphql_schema = nil
      end

      # The generated schema, built on first use since finalizing reads the database's columns.
      # @return [Class] a GraphQL::Schema subclass
      def graphql_schema
        @graphql_schema ||= SchemaBuilder.new(@graphql_resources || [], max_depth: @graphql_max_depth).build
      end
    end
  end
end
