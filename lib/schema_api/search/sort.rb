# frozen_string_literal: true

module SchemaApi
  module Search
    # Parses ?sort=-year,created_at against the declared sort fields. The primary key is
    # always added last, so the order is stable and cursors are exact.
    class Sort
      # A parsed sort.
      #
      # @!attribute columns
      #   @return [Array<Array(String, Symbol)>] [column, :asc or :desc], primary key last
      Order = Struct.new(:columns) do
        # @return [String] identifies the sort, so a cursor can't be reused with another one
        def signature
          columns.map { |column, direction| "#{'-' if direction == :desc}#{column}" }.join(',')
        end
      end

      # @param model [Class]
      # @param allowed [Hash{String => String}] sort field => column
      # @param default [String, nil]
      def initialize(model, allowed, default)
        @model = model
        @allowed = allowed
        @default = default
      end

      # @param value [String, Array, nil]
      # @return [Array(Order, Array<Hash>)] the order, and error details for unknown fields
      def parse(value)
        tokens = value.nil? || value == '' ? @default.to_s.split(',') : Array(value).flat_map { |v| v.to_s.split(',') }
        errors = []
        columns = tokens.map(&:strip).reject(&:empty?).filter_map do |token|
          name = token.delete_prefix('-')
          next [@allowed[name], token.start_with?('-') ? :desc : :asc] if @allowed.key?(name)

          errors << { field: 'sort', error: 'invalid', message: "Sort by #{name} is not allowed" }
          nil
        end
        [Order.new(with_primary_key(columns)), errors]
      end

      private

      def with_primary_key(columns)
        primary_key = @model.primary_key
        return columns if columns.any? { |column, _| column == primary_key }

        columns + [[primary_key, columns.last&.last || :asc]]
      end
    end
  end
end
