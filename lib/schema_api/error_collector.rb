# frozen_string_literal: true

module SchemaApi
  # Walks a schema tree (any schema-model schema) and collects its parsing or validation
  # errors as details, with paths that match the request: "email", "address.zip", "items[1].quantity".
  class ErrorCollector
    # Parsing errors at every level. Markers schema-model leaves on a parent for a nested
    # model's errors (e.g. "items:1") are replaced by the nested model's own errors.
    # @param schema [Schema::Model]
    # @param path [String, nil]
    # @return [Array<Hash>]
    def parsing_details(schema, path = nil)
      details = schema.parsing_errors.filter_map do |error|
        next if nested_marker?(schema, error.attribute.to_s)

        parsing_detail(error, path)
      end
      each_child(schema, path) { |child, child_path| details.concat(parsing_details(child, child_path)) }
      details
    end

    # Runs validations at every level and collects their errors. belongs_to objects are
    # skipped (they're never written), as are has_many items marked _destroy.
    # @param schema [Schema::Model]
    # @param context [Symbol] validation context, :create or :update
    # @param path [String, nil]
    # @return [Array<Hash>]
    def validation_details(schema, context, path = nil)
      schema.valid?(context)
      details = schema.errors.filter_map do |error|
        next if association_field?(schema, error.attribute)

        { field: join(path, error.attribute), error: error_code(error), message: error.full_message }
      end
      each_child(schema, path, writable_only: true) do |child, child_path|
        details.concat(validation_details(child, context, child_path))
      end
      details
    end

    private

    def parsing_detail(error, path)
      field = error.attribute == :base ? path : join(path, display_name(error.attribute.to_s))
      message = error.attribute == :base ? "Value #{error.message}" : error.full_message
      { field: field, error: error.type.to_s, message: message }
    end

    # "items:1" or "profile" with a nested model present: its own errors are reported instead
    def nested_marker?(schema, attribute)
      name, index = attribute.split(':', 2)
      field = field_for(schema, name)
      return false unless field&.association?

      value = schema.public_send(field.getter)
      index ? value.is_a?(Array) && !value[index.to_i].nil? : !value.nil?
    end

    def display_name(attribute)
      name, index = attribute.split(':', 2)
      index ? "#{name}[#{index}]" : name
    end

    def each_child(schema, path, writable_only: false, &)
      fields_for(schema).select(&:association?).each do |field|
        next if writable_only && field.belongs_to?

        value = schema.public_send(field.getter)
        next each_list_child(value, join(path, field.name), writable_only, &) if value.is_a?(Array)

        yield value, join(path, field.name) if value
      end
    end

    def each_list_child(children, path, writable_only)
      children.each_with_index do |child, index|
        next if child.nil? || (writable_only && destroyed?(child))

        yield child, "#{path}[#{index}]"
      end
    end

    def destroyed?(child)
      child.respond_to?(:_destroy) && child._destroy == true
    end

    def association_field?(schema, attribute)
      field_for(schema, attribute)&.association? || false
    end

    # plain schema-model options, so schemas without SchemaApi::ResourceSchema work too
    def fields_for(schema)
      schema.class.schema.each_value.reject { |options| options[:alias_of] }.map { |options| Field.new(options, schema.class) }
    end

    def field_for(schema, name)
      options = schema.class.schema[name.to_sym]
      options && Field.new(options, schema.class)
    end

    def error_code(error)
      error.type.is_a?(Symbol) ? error.type.to_s : 'invalid'
    end

    def join(path, name)
      path ? "#{path}.#{name}" : name.to_s
    end
  end
end
