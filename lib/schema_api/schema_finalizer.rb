# frozen_string_literal: true

module SchemaApi
  # Finalizes a schema class and its nested classes against the model: gives model
  # attributes their types, works out what backs each nested schema, checks belongs_to
  # scopes and match keys, and compiles the mappings.
  class SchemaFinalizer
    # @param schema_class [Class]
    # @param model [Class, nil] nil inside a JSON-backed schema
    # @param path [String] for error messages, e.g. "CarsController.owners"
    def initialize(schema_class, model, path:)
      @schema_class = schema_class
      @model = model
      @path = path
    end

    # @return [Class] the schema class
    def finalize!
      return @schema_class if @schema_class.finalized?

      @schema_class.schema_model = @model
      resolve_model_attributes
      @schema_class.api_fields.select(&:association?).each { |field| finalize_association(field) }
      check_values_of
      check_server_fields
      @schema_class.api_mappings = MappingBuilder.new(@schema_class).build
      @schema_class.mark_finalized!
      @schema_class
    end

    private

    def resolve_model_attributes
      @schema_class.api_fields.select(&:pending?).each do |field|
        column, model = field.reference_key? ? reference_column(field) : [field.model_name, @model]
        type, extra = model && TypeResolver.new(model).resolve(column)
        raise UnknownAttributeError, unknown_attribute_message(field, model, column) unless type

        extra[:column] = column.to_s if field.reference_key? && model == @model
        redeclare(field, type, extra)
      end
    end

    def redeclare(field, type, extra)
      declared = field.declared_options
      enum_values = extra.delete(:enum_values)
      @schema_class.attribute(field.name, type, declared.merge(extra).merge(model_attribute: true, declared_options: declared))
      @schema_class.validates(field.name, inclusion: { in: enum_values }, allow_nil: true) if enum_values
    end

    # a belongs_to key is typed by the foreign key (key: :id) or the referenced model's key column
    def reference_column(field)
      reflection = belongs_to_reflection(@schema_class.api_field(field.reference_for))
      key = @schema_class.api_field(field.reference_for).reference[:key]
      key == :id ? [reflection.foreign_key, @model] : [key, reflection.klass]
    end

    def finalize_association(field)
      if field.belongs_to?
        finalize_reference(field)
      elsif (reflection = @model&.reflect_on_association(field.model_name))
        finalize_owned(field, reflection)
      elsif @model.nil? || TypeResolver.new(@model).json?(field.model_name)
        finish_nested(field, :json, nil)
      else
        raise UnknownAttributeError, "#{path(field.name)}: #{@model} has no association or json column #{field.model_name}"
      end
    end

    def finalize_reference(field)
      reflection = belongs_to_reflection(field)
      if field.reference[:input] && field.reference[:scope].nil?
        raise MissingScopeError,
              "#{path(field.name)}: belongs_to with input: true needs scope: (a controller method, a lambda, or :all)"
      end
      finish_nested(field, :reference, reflection.klass)
    end

    def finalize_owned(field, reflection)
      if field.writable? && reflection.through_reflection?
        raise DefinitionError, "#{path(field.name)}: has_many :through associations can't be written; drop input:"
      end

      add_destroy_flag(field) if field.has_many? && field.writable?
      finish_nested(field, :association, reflection.klass)
      check_match_keys(field) if field.has_many?
    end

    def finish_nested(field, backing, model)
      nested = field.nested_class
      nested.api_backing = backing
      SchemaFinalizer.new(nested, model, path: path(field.name)).finalize!
    end

    def add_destroy_flag(field)
      nested = field.nested_class
      return if nested.finalized? || nested.schema.key?(:_destroy)

      nested.attribute(:_destroy, :boolean, model: false, destroy_flag: true)
    end

    def check_match_keys(field)
      missing = field.match_keys.reject { |key| field.nested_class.api_field(key) }
      return if missing.empty?

      raise DefinitionError, "#{path(field.name)}: key #{missing.join(', ')} isn't an attribute of the nested schema"
    end

    def check_values_of
      @schema_class.api_fields.select(&:values_of).each do |field|
        next if @model&.reflect_on_association(field.values_of[:association])

        raise UnknownAttributeError, "#{path(field.name)}: #{@model} has no association #{field.values_of[:association]}"
      end
    end

    # a field the server sets can't also be written by the client
    def check_server_fields
      @schema_class.api_fields.select(&:server_value).each do |field|
        next unless field.writable?

        raise DefinitionError, "#{path(field.name)}: set: fields are set by the server; drop input:/write_only:"
      end
    end

    def belongs_to_reflection(field)
      reflection = @model&.reflect_on_association(field.model_name)
      return reflection if reflection&.belongs_to?

      raise UnknownAttributeError, "#{path(field.name)}: #{@model} has no belongs_to #{field.model_name}"
    end

    def unknown_attribute_message(field, model, column)
      return "#{path(field.name)}: model_attribute needs a type inside a JSON-backed schema" unless model

      "#{path(field.name)}: #{model} has no attribute #{column}"
    end

    def path(name)
      "#{@path}.#{name}"
    end
  end
end
