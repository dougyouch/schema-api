# frozen_string_literal: true

module SchemaApi
  # Create-only fields may be sent on update (clients send back what they got), but only
  # with the value already stored.
  module CreateOnlyCheck
    module_function

    # @param schema [Schema::Model] input for an existing record
    # @param record [ActiveRecord::Base]
    # @param path [String, nil]
    # @return [Array<Hash>] a create_only_attribute detail per changed field
    def details(schema, record, path)
      schema.class.api_fields.select(&:create_only?).filter_map do |field|
        next unless field.set_in?(schema)
        next if field.model_name.nil?
        next if ValueComparer.same?(schema.public_send(field.getter), record.public_send(field.model_name))

        name = path ? "#{path}.#{field.name}" : field.name.to_s
        { field: name, error: 'create_only_attribute', message: "#{field.name.to_s.humanize} can only be set on create" }
      end
    end
  end
end
