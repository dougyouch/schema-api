# frozen_string_literal: true

module SchemaApi
  # Parses data with any schema-model schema and raises in SchemaApi's error format, for
  # endpoints that aren't resources (a search form, an /authorize check).
  class SchemaParser
    # @param schema_class [Class] a Schema::All class
    def initialize(schema_class)
      @schema_class = schema_class
    end

    # @param data [Hash]
    # @param context [Symbol, nil] validation context
    # @return [Schema::Model]
    # @raise [InvalidData] when anything didn't parse (validation errors are included)
    # @raise [ValidationError] when validations failed
    def parse!(data, context: nil)
      schema = @schema_class.from_hash(data)
      collector = ErrorCollector.new
      details = collector.parsing_details(schema) + collector.validation_details(schema, context)
      return schema if details.empty?

      error_class = schema.parsed? ? ValidationError : InvalidData
      raise error_class.new("#{@schema_class.name&.demodulize || 'Input'} is invalid", details: details)
    end
  end
end
