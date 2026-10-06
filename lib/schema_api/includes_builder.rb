# frozen_string_literal: true

module SchemaApi
  # Builds the eager-loading tree for a schema, so rendering a list doesn't run a query per
  # nested record: { owners: {}, manufacturer: {}, affiliations: { roles: {} } }. Computed fields
  # add what they declare with includes:.
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
        elsif field.value_includes
          tree.deep_merge!(IncludesBuilder.normalize(field.value_includes))
        elsif loaded_association?(field)
          tree[field.model_name] = IncludesBuilder.new(field.nested_class).build
        end
      end
    end

    # :a, [:a, { b: :c }] or { a: :b } as a nested hash: { a: {}, b: { c: {} } }
    # @api private
    def self.normalize(includes)
      case includes
      when Hash then includes.to_h { |name, nested| [name.to_sym, normalize(nested)] }
      when Array then includes.map { |entry| normalize(entry) }.reduce({}, :deep_merge)
      else { includes.to_sym => {} }
      end
    end

    private

    def loaded_association?(field)
      field.association? && field.includes? && %i[association reference].include?(field.backing)
    end
  end
end
