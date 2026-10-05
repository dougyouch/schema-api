# frozen_string_literal: true

module SchemaApi
  module Pagination
    # A controller's pagination: modes, limits and whether to count.
    #
    #   paginate :cursor, limit: { default: 25, max: 100 }        # the default
    #   paginate :offset, count: true                             # ?page=, meta.total_count
    #   paginate %i[cursor offset], count: :optional              # client picks; ?count=true counts
    class Config
      # Supported modes.
      MODES = %i[cursor offset].freeze

      # @return [Array<Symbol>]
      attr_reader :modes
      # @return [Integer]
      attr_reader :default_limit
      # @return [Integer]
      attr_reader :max_limit
      # @return [Boolean, Symbol] true, :optional or false
      attr_reader :count

      # @param modes [Symbol, Array<Symbol>]
      # @param limit [Hash] default: (25) and max: (100)
      # @param count [Boolean, Symbol]
      def initialize(modes = :cursor, limit: {}, count: false)
        @modes = Array(modes).map(&:to_sym)
        unknown = @modes - MODES
        raise DefinitionError, "paginate: unknown mode #{unknown.join(', ')}" if unknown.any? || @modes.empty?

        @default_limit = limit.fetch(:default, 25)
        @max_limit = limit.fetch(:max, 100)
        @count = count
      end

      # @return [Hash{String => Symbol}] pagination parameters this config accepts, with their types
      def param_types
        types = { 'sort' => :string, 'limit' => :integer }
        types['cursor'] = :string if modes.include?(:cursor)
        types['page'] = :integer if modes.include?(:offset)
        types['count'] = :boolean if count == :optional
        types
      end

      # @return [Array<String>]
      def param_names
        param_types.keys
      end

      # @param scope [ActiveRecord::Relation] filtered and sorted
      # @param query [Search::Query]
      # @return [Page]
      def paginate(scope, query)
        paginator = offset?(query) ? Offset : Cursor
        paginator.new(self).paginate(scope, query)
      end

      # @param query [Search::Query]
      # @return [Boolean] whether to add meta.total_count
      def count?(query)
        count == true || (count == :optional && query.count == true)
      end

      # @param query [Search::Query]
      # @return [Integer]
      def limit_for(query)
        query.limit || default_limit
      end

      private

      def offset?(query)
        modes == [:offset] || (modes.include?(:offset) && !query.page.nil?)
      end
    end
  end
end
