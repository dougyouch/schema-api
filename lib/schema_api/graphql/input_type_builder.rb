# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Builds GraphQL input types from schema classes: what a mutation may send. That's the
    # writable fields (input:, write_only:, belongs_to keys, value lists), lock fields, and on
    # has_many items, _destroy, plus id when items are matched by id (key: picks other fields). Output-only
    # fields, server-set fields and belongs_to objects aren't inputs. Every field is optional,
    # so an update sends only what changes; validations report what a create is missing.
    # A JSON-backed nested schema is stored whole, so all of its fields are inputs.
    class InputTypeBuilder
      DESCRIPTIONS = {
        create_only: 'Set on create only; sending a different value later is a create_only_attribute error',
        lock: 'The value last read; the write fails with stale_resource if it has changed since',
        destroy: 'true removes this item'
      }.freeze

      def initialize
        @types = {}
      end

      # @param schema_class [Class]
      # @param name [String] the object type's name; the input type is "<name>Input"
      # @param root [Boolean] the resource itself, whose id comes from the mutation's id argument
      # @return [Class, nil] a GraphQL::Schema::InputObject subclass, nil when nothing is writable
      def input_type(schema_class, name, root: false)
        input_type_for(schema_class, name, root ? :root : :nested)
      end

      private

      def build(schema_class, name, level)
        arguments = schema_class.api_fields.filter_map do |field|
          next unless input_field?(field, level)

          argument_type = argument_type(field, name)
          [field, argument_type] if argument_type
        end
        arguments.empty? ? nil : input_object(name, arguments)
      end

      def input_object(name, arguments)
        type = Class.new(::GraphQL::Schema::InputObject)
        type.graphql_name("#{name}Input")
        arguments.each do |field, argument_type|
          type.argument(field.name, argument_type, required: false, camelize: false, description: description(field))
        end
        type
      end

      # level: :root, :nested, :json, or :matched_by_id for has_many items matched by id
      def input_field?(field, level)
        return false if field.belongs_to?
        return true if level == :json || field.writable? || field.lock? || field.destroy_flag?

        level == :matched_by_id && field.name == :id
      end

      def argument_type(field, owner_name)
        return ScalarTypes.for_argument(field.type, field.options) unless field.association?

        nested_name = "#{owner_name}#{field.name.to_s.camelize.singularize}"
        nested = input_type_for(field.nested_class, nested_name, nested_level(field))
        return unless nested

        field.has_many? ? [nested] : nested
      end

      def input_type_for(schema_class, name, level)
        return @types[schema_class] if @types.key?(schema_class)

        @types[schema_class] = build(schema_class, name, level)
      end

      def nested_level(field)
        return :json if field.backing == :json

        field.has_many? && field.match_keys.include?(:id) ? :matched_by_id : :nested
      end

      def description(field)
        return DESCRIPTIONS[:create_only] if field.create_only?
        return DESCRIPTIONS[:lock] if field.lock?

        DESCRIPTIONS[:destroy] if field.destroy_flag?
      end
    end
  end
end
