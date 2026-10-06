# frozen_string_literal: true

module SchemaApi
  module Graphql
    # GraphQL types for schema-model value types, matching how the Serializer renders them:
    # times, dates and decimals are strings, a unix time is an integer.
    module ScalarTypes
      # schema type => GraphQL type
      TYPES = {
        integer: ::GraphQL::Types::Int,
        string: ::GraphQL::Types::String,
        boolean: ::GraphQL::Types::Boolean,
        float: ::GraphQL::Types::Float,
        decimal: ::GraphQL::Types::String,
        date: ::GraphQL::Types::String,
        time: ::GraphQL::Types::String,
        datetime: ::GraphQL::Types::String,
        hash: ::GraphQL::Types::JSON
      }.freeze

      module_function

      # @param field [Field] a rendered, non-association field
      # @return [Class, Array<Class>]
      def for_field(field)
        return [value_type(field.options[:data_type])] if field.type == :array
        return time_type(field.format) if %i[time datetime].include?(field.type)

        value_type(field.type)
      end

      # @param type [Symbol, nil] a schema type
      # @param options [Hash] schema-model attribute options; data_type: for arrays
      # @return [Class, Array<Class>] the type of a value sent as an argument
      def for_argument(type, options = {})
        return [value_type(options[:data_type])] if type == :array

        value_type(type)
      end

      # untyped values (arrays without a data_type, unknown types) are JSON
      def value_type(type)
        TYPES.fetch(type&.to_sym, ::GraphQL::Types::JSON)
      end

      def time_type(format)
        case format
        when :unix then ::GraphQL::Types::Int
        when Proc then ::GraphQL::Types::JSON
        else ::GraphQL::Types::String
        end
      end
    end
  end
end
