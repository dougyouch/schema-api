# frozen_string_literal: true

module SchemaApi
  # Builds a schema tree from a record: scalars through the output mapping, then nested
  # associations, JSON columns, belongs_to objects and value lists.
  class Presenter
    # @param record [ActiveRecord::Base]
    # @param schema_class [Class]
    # @return [Schema::Model]
    def present(record, schema_class)
      schema = schema_class.api_mappings.output.new.map(record, schema_class.new)
      schema_class.api_fields.each { |field| present_field(schema, record, field) }
      schema
    end

    private

    def present_field(schema, record, field)
      if field.association?
        schema.instance_variable_set(field.instance_variable, nested_value(record, field))
      elsif field.values_of
        schema.public_send(field.setter, record.public_send(field.values_of[:association]).map(&field.values_of[:field]))
      elsif field.reference_key? && field.output?
        schema.public_send(field.setter, reference_key_value(record, schema.class.api_field(field.reference_for)))
      end
    end

    def nested_value(record, field)
      value = record.public_send(field.model_name)
      return json_value(value, field) if field.backing == :json
      return value.map { |child| present(child, field.nested_class) } if field.has_many?

      value && present(value, field.nested_class)
    end

    # stored JSON may have keys the schema no longer declares, so nothing is reported here
    def json_value(value, field)
      return value&.map { |data| field.nested_class.from_hash(data) } if field.has_many?

      value && field.nested_class.from_hash(value)
    end

    def reference_key_value(record, reference_field)
      key = reference_field.reference[:key]
      reflection = record.class.reflect_on_association(reference_field.model_name)
      return record.public_send(reflection.foreign_key) if key == :id

      record.public_send(reference_field.model_name)&.public_send(key)
    end
  end
end
