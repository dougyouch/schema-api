# frozen_string_literal: true

module SchemaApi
  module Graphql
    # The endpoint's action.
    module Execution
      # POST /graphql with { "query": "...", "variables": {...}, "operationName": "..." }.
      # Errors inside the query are reported in the GraphQL response's errors, with status 200;
      # a body that isn't a GraphQL request is a 400 malformed_request.
      def execute
        graphql_request = RequestParser.new(request.raw_post).parse
        result = self.class.graphql_schema.execute(
          graphql_request.query,
          variables: graphql_request.variables,
          operation_name: graphql_request.operation_name,
          context: graphql_context
        )
        render json: result.to_h
      end

      private

      # Override to add to the context resolvers see.
      # @return [Hash]
      def graphql_context
        { request: request, logger: logger }
      end
    end
  end
end
