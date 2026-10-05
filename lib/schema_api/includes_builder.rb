# frozen_string_literal: true

module SchemaApi
  # Builds the eager-loading tree for a schema, so rendering a list doesn't run a query per
  # nested record: { owners: {}, manufacturer: {}, affiliations: { roles: {} } }
  class IncludesBuilder
    # @param schema_class [Class]
    def initialize(schema_class)
      @schema_class = schema_class
    end

    # @return [Hash]
    def build
      @schema_class.api_fields.each_with_object({}) do |field, tree|
        if field.values_of
          tree[field.values_of[:association]] = {}
        elsif loaded_association?(field)
          tree[field.model_name] = IncludesBuilder.new(field.nested_class).build
        end
      end
    end

    private

    def loaded_association?(field)
      field.association? && field.includes? && %i[association reference].include?(field.backing)
    end
  end
end
