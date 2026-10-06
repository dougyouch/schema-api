# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Builds a list field's filter argument from a controller's search filters, and turns the
    # argument's value back into the search params the REST index takes, so the same
    # {Search::ParamsParser} checks it:
    #
    #   filter :year, op: %i[gte lte]   =>  users(filter: { year: { gte: 2010 } })  =>  { "year" => { "gte" => 2010 } }
    #
    # Each filter is an input object with one field per operator. Dots in nested filter names
    # become underscores: owners.person_id is owners_person_id.
    class FilterTypeBuilder
      # @param search [Search::Definition] finalized
      # @param type_name [String] the resource's GraphQL type name
      def initialize(search, type_name)
        @search = search
        @type_name = type_name
        @filter_names = argument_names
      end

      # @return [Boolean]
      def filters?
        @search.filters.any?
      end

      # @return [Class] a GraphQL::Schema::InputObject subclass
      def build
        type = Class.new(::GraphQL::Schema::InputObject)
        type.graphql_name("#{@type_name}Filter")
        @filter_names.each do |argument, filter_name|
          type.argument(argument, filter_type(@search.filters[filter_name]), required: false, camelize: false)
        end
        type
      end

      # @param filter [Hash, nil] the filter argument's value
      # @return [Hash{String => Hash}] search params
      def to_params(filter)
        filter.to_h.each_with_object({}) do |(argument, ops), params|
          params[@filter_names.fetch(argument.to_s)] = ops.to_h.transform_keys(&:to_s)
        end
      end

      private

      def argument_names
        names = @search.filters.keys.to_h { |filter_name| [filter_name.tr('.', '_'), filter_name] }
        return names if names.size == @search.filters.size

        raise DefinitionError, "#{@type_name} filters: two filters have the same GraphQL name once dots become underscores"
      end

      def filter_type(filter)
        type = Class.new(::GraphQL::Schema::InputObject)
        type.graphql_name("#{@type_name}#{filter.name.tr('.', '_').camelize}Filter")
        filter.ops.each do |op|
          type.argument(op, ScalarTypes.for_argument(*filter.param_type(op)), required: false, camelize: false)
        end
        type
      end
    end
  end
end
