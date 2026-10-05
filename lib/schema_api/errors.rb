# frozen_string_literal: true

module SchemaApi
  # Base class for errors rendered as API responses. Each has a machine `code`, an HTTP
  # `status` and a list of `details` ({ field:, error:, message: }).
  class Error < StandardError
    # @return [Array<Hash>]
    attr_reader :details

    # @param message [String]
    # @param details [Array<Hash>]
    def initialize(message = nil, details: [])
      super(message || default_message)
      @details = details
    end

    # @return [String]
    def code
      self.class::CODE
    end

    # @return [Symbol, Integer]
    def status
      self.class::STATUS
    end

    private

    def default_message
      code.tr('_', ' ').capitalize
    end
  end

  # 400: the body isn't JSON, or isn't shaped as expected.
  class MalformedRequest < Error
    CODE = 'malformed_request'
    STATUS = :bad_request
  end

  # 400: values that don't parse, unknown fields, or fields the client can't write.
  class InvalidData < Error
    CODE = 'invalid_data'
    STATUS = :bad_request
  end

  # 403: writing or reading something the viewer isn't allowed to.
  class Forbidden < Error
    CODE = 'forbidden'
    STATUS = :forbidden
  end

  # 404: the resource doesn't exist, or isn't in scope.
  class NotFound < Error
    CODE = 'not_found'
    STATUS = :not_found
  end

  # 409: a unique constraint was violated.
  class Conflict < Error
    CODE = 'conflict'
    STATUS = :conflict
  end

  # 409: the optimistic lock value sent doesn't match the stored one.
  class StaleResource < Error
    CODE = 'stale_resource'
    STATUS = :conflict
  end

  # 422: schema, controller or model validations failed.
  class ValidationError < Error
    CODE = 'validation_error'
    STATUS = 422 # :unprocessable_content on Rack 3.1+, :unprocessable_entity before
  end

  # Raised while declaring or finalizing a schema; a programming error, not a client error.
  class DefinitionError < StandardError; end

  # A model_attribute, association or filter names something the model doesn't have.
  class UnknownAttributeError < DefinitionError; end

  # A writable belongs_to without a scope:.
  class MissingScopeError < DefinitionError; end

  # A model_attribute was used before the schema was finalized.
  class NotFinalizedError < DefinitionError; end
end
