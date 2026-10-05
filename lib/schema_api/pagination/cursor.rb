# frozen_string_literal: true

module SchemaApi
  module Pagination
    # Keyset pagination: the cursor holds the sort values of the last record, and the next
    # page starts after them. Fast on large tables, and rows added or removed between pages
    # don't cause skips or repeats. Sort columns should be NOT NULL.
    class Cursor
      # @param order [Search::Sort::Order]
      # @param record [ActiveRecord::Base]
      # @return [String] an opaque token
      def self.encode(order, record)
        values = order.columns.map { |column, _| dump(record.public_send(column)) }
        Base64.urlsafe_encode64(JSON.generate('s' => order.signature, 'v' => values), padding: false)
      end

      # @param token [String]
      # @param order [Search::Sort::Order]
      # @return [Array] the sort values
      # @raise [ArgumentError] when the token is malformed or was made for another sort
      def self.decode(token, order)
        data = JSON.parse(Base64.urlsafe_decode64(token))
        raise ArgumentError, 'cursor sort mismatch' unless data.is_a?(Hash) && data['s'] == order.signature
        raise ArgumentError, 'cursor size mismatch' unless data['v'].is_a?(Array) && data['v'].size == order.columns.size

        data['v'].map { |value| load(value) }
      rescue JSON::ParserError, TypeError
        raise ArgumentError, 'malformed cursor'
      end

      # @api private
      def self.dump(value)
        case value
        when Time, DateTime, ActiveSupport::TimeWithZone then { 't' => value.iso8601(9) }
        when Date then { 'd' => value.iso8601 }
        when BigDecimal then { 'n' => value.to_s('F') }
        else value
        end
      end

      # @api private
      def self.load(value)
        return value unless value.is_a?(Hash)
        return Time.iso8601(value['t']) if value.key?('t')
        return Date.iso8601(value['d']) if value.key?('d')
        return BigDecimal(value['n']) if value.key?('n')

        raise ArgumentError, 'malformed cursor value'
      end

      # @param config [Config]
      def initialize(config)
        @config = config
      end

      # @param scope [ActiveRecord::Relation]
      # @param query [Search::Query]
      # @return [Page]
      def paginate(scope, query)
        limit = @config.limit_for(query)
        paged = query.cursor_values ? scope.where(after(scope, query)) : scope
        records = paged.limit(limit + 1).to_a
        more = records.size > limit
        records = records.first(limit)
        meta = { limit: limit, next_cursor: more ? Cursor.encode(query.order, records.last) : nil }
        meta[:total_count] = scope.unscope(:order).count if @config.count?(query)
        Page.new(records, meta)
      end

      private

      # (c1 > v1) OR (c1 = v1 AND c2 > v2) OR ..., with < for descending columns
      def after(scope, query)
        table = scope.klass.arel_table
        columns = query.order.columns.zip(query.cursor_values)
        branches = columns.each_index.map do |index|
          equal = columns.first(index).map { |(column, _), value| table[column].eq(value) }
          (column, direction), value = columns[index]
          compare = direction == :desc ? table[column].lt(value) : table[column].gt(value)
          (equal + [compare]).reduce { |left, right| left.and(right) }
        end
        Arel::Nodes::Grouping.new(branches.reduce { |left, right| left.or(right) })
      end
    end
  end
end
