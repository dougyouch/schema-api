# frozen_string_literal: true

module SchemaApi
  module Search
    # A parsed search: filter conditions, sort order and pagination parameters.
    class Query
      # @return [Array<Array(Filter, Symbol, Object)>] [filter, operator, value]
      attr_reader :conditions
      # @return [Sort::Order]
      attr_reader :order
      # @return [Integer, nil]
      attr_reader :limit
      # @return [Array, nil] decoded cursor values
      attr_reader :cursor_values
      # @return [Integer, nil]
      attr_reader :page
      # @return [Boolean, nil]
      attr_reader :count

      # @param attributes [Hash] conditions:, order:, limit:, cursor_values:, page:, count:
      def initialize(**attributes)
        attributes.each { |name, value| instance_variable_set(:"@#{name}", value) }
      end

      # @param scope [ActiveRecord::Relation]
      # @param controller [ActionController::Metal]
      # @return [ActiveRecord::Relation] filtered and ordered
      def apply(scope, controller)
        filtered = conditions.reduce(scope) { |current, (filter, op, value)| filter.apply(current, op, value, controller) }
        table = filtered.klass.arel_table
        filtered.reorder(order.columns.map { |column, direction| table[column].public_send(direction) })
      end
    end
  end
end
