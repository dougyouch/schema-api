# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Turns a {SchemaApi::Error} raised while resolving a field into a GraphQL error. The field
    # is null, its siblings still resolve, and the error carries SchemaApi's code, HTTP status
    # and details in extensions:
    #
    #   { "message": "A session or application token is required", "path": ["users"],
    #     "extensions": { "code": "unauthorized", "status": 401, "details": [] } }
    class ErrorHandler
      # @param context [GraphQL::Query::Context]
      def initialize(context)
        @context = context
      end

      # @param error [SchemaApi::Error]
      # @param field [GraphQL::Schema::Field]
      # @raise [GraphQL::ExecutionError]
      def handle(error, field)
        log(error, field)
        raise ::GraphQL::ExecutionError.new(error.message, extensions: extensions(error))
      end

      private

      def extensions(error)
        { code: error.code, status: Rack::Utils.status_code(error.status),
          details: ErrorSchema.from_error(error).to_response[:error][:details] }
      end

      def log(error, field)
        @context[:logger]&.info(
          "SchemaApi GraphQL #{field&.path} #{error.code}: #{error.message} #{error.details.to_json}"
        )
      end
    end
  end
end
