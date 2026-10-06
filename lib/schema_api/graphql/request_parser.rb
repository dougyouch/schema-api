# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Reads a GraphQL request body: query, variables and operationName.
    class RequestParser
      # A parsed request.
      Request = Struct.new(:query, :variables, :operation_name)

      # @param body [String] the raw request body
      def initialize(body)
        @body = body
      end

      # @return [Request]
      # @raise [MalformedRequest]
      def parse
        data = json_object(@body, 'Request body')
        query = data['query']
        raise MalformedRequest, 'query is required' unless query.is_a?(String) && !query.strip.empty?

        Request.new(query, variables(data['variables']), operation_name(data['operationName']))
      end

      private

      def json_object(text, label)
        data = JSON.parse(text.to_s)
        raise MalformedRequest, "#{label} must be a JSON object" unless data.is_a?(Hash)

        data
      rescue JSON::ParserError
        raise MalformedRequest, "#{label} is not valid JSON"
      end

      # some clients send variables as a JSON string
      def variables(value)
        case value
        when nil then {}
        when Hash then value
        when String then value.strip.empty? ? {} : json_object(value, 'variables')
        else raise MalformedRequest, 'variables must be an object'
        end
      end

      def operation_name(value)
        return value if value.nil? || value.is_a?(String)

        raise MalformedRequest, 'operationName must be a string'
      end
    end
  end
end
