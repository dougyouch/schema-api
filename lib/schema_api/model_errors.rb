# frozen_string_literal: true

module SchemaApi
  # Turns a record's ActiveModel errors into details named the way the API names them:
  # a model attribute mapped from another schema field uses that field's name, and a
  # belongs_to error ("Manufacturer must exist") is reported on its key field.
  class ModelErrors
    # @param record [ActiveRecord::Base]
    # @param schema_class [Class]
    # @param path [String, nil]
    def initialize(record, schema_class, path)
      @record = record
      @schema_class = schema_class
      @path = path
    end

    # @return [Array<Hash>]
    def details
      @record.errors.map do |error|
        { field: field_path(error.attribute), error: error.type.is_a?(Symbol) ? error.type.to_s : 'invalid',
          message: error.full_message }
      end
    end

    private

    def field_path(attribute)
      return @path if attribute == :base

      name = api_name(attribute)
      @path ? "#{@path}.#{name}" : name.to_s
    end

    def api_name(attribute)
      field = @schema_class.api_fields.find { |f| f.model_name == attribute && !f.reference_key? }
      return attribute unless field
      return field.reference[:key_field] if field.belongs_to?

      field.name
    end
  end
end
