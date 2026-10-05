# frozen_string_literal: true

module SchemaApi
  # Reads a JSON request body and returns what's under its root key. Requests are wrapped
  # the same way responses are: { "car": {...} } or { "cars": [...] }.
  class InputParser
    # @param raw_body [String]
    # @param root_key [String]
    def initialize(raw_body, root_key)
      @raw_body = raw_body
      @root_key = root_key.to_s
    end

    # @return [Hash]
    # @raise [MalformedRequest] when the body isn't JSON or has no object under the root key
    def object
      value = root_value
      return value if value.is_a?(Hash)

      raise MalformedRequest, "Expected an object under \"#{@root_key}\""
    end

    # @param max [Integer, nil] most items allowed
    # @return [Array]
    # @raise [MalformedRequest] when the body isn't JSON, has no list under the root key, or the list is too long
    def list(max: nil)
      value = root_value
      raise MalformedRequest, "Expected a list under \"#{@root_key}\"" unless value.is_a?(Array)
      raise MalformedRequest, "At most #{max} items are allowed per request" if max && value.size > max

      value
    end

    private

    def root_value
      body = parse_body
      raise MalformedRequest, "Expected a JSON object with a \"#{@root_key}\" key" unless body.is_a?(Hash) && body.key?(@root_key)

      body[@root_key]
    end

    def parse_body
      raise MalformedRequest, 'Request body is empty' if @raw_body.to_s.strip.empty?

      JSON.parse(@raw_body)
    rescue JSON::ParserError
      raise MalformedRequest, 'Request body is not valid JSON'
    end
  end
end
