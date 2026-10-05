# frozen_string_literal: true

module SchemaApi
  # The error response, the same for every failure:
  #
  #   { "error": { "code": "validation_error", "message": "Car is invalid",
  #                "details": [{ "field": "make", "error": "blank", "message": "Make can't be blank" }] } }
  class ErrorSchema
    include ::Schema::All

    has_one(:error) do
      attribute :code, :string
      attribute :message, :string

      has_many(:details) do
        attribute :field, :string
        attribute :error, :string
        attribute :message, :string
      end
    end

    # @param error [SchemaApi::Error]
    # @return [ErrorSchema]
    def self.from_error(error)
      from_hash(error: { code: error.code, message: error.message, details: error.details })
    end

    # @return [Hash] the response body; details always present, field nil when the error is about the whole item
    def to_response
      { error: { code: error.code, message: error.message, details: error.details.map(&:to_hash) } }
    end
  end
end
