# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Builds GraphQL object types from schema classes. Fields are the schema's rendered fields
    # (write-only fields never appear), snake_case as in the REST JSON, and resolve from the
    # hash resource_json returns, so values are formatted exactly as REST renders them.
    # Nested types are named by their path: User, UserAffiliation, UserAffiliationOrganization.
    class TypeBuilder
      def initialize
        @types = {}
      end

      # @param schema_class [Class]
      # @param name [String] GraphQL type name
      # @return [Class] a GraphQL::Schema::Object subclass
      def object_type(schema_class, name)
        @types[schema_class] ||= build_object_type(schema_class, name)
      end

      private

      def build_object_type(schema_class, name)
        type = Class.new(::GraphQL::Schema::Object) { graphql_name(name) }
        schema_class.api_fields.select(&:output?).each do |field|
          type.field(field.name, field_type(field, name), null: true, camelize: false, hash_key: field.name,
                                                          method_conflict_warning: false)
        end
        type
      end

      def field_type(field, owner_name)
        return ScalarTypes.for_field(field) unless field.association?

        nested = object_type(field.nested_class, "#{owner_name}#{field.name.to_s.camelize.singularize}")
        field.has_many? ? [nested] : nested
      end
    end
  end
end
