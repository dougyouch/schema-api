# frozen_string_literal: true

module SchemaApi
  module Pagination
    # Page-number pagination, for small tables and UIs that show page numbers.
    class Offset
      # @param config [Config]
      def initialize(config)
        @config = config
      end

      # @param scope [ActiveRecord::Relation]
      # @param query [Search::Query]
      # @return [Page]
      def paginate(scope, query)
        limit = @config.limit_for(query)
        page = query.page || 1
        records = scope.offset((page - 1) * limit).limit(limit + 1).to_a
        more = records.size > limit
        meta = { limit: limit, page: page, next_page: more ? page + 1 : nil }
        add_counts(meta, scope, limit) if @config.count?(query)
        Page.new(records.first(limit), meta)
      end

      private

      def add_counts(meta, scope, limit)
        total = scope.unscope(:order).count
        meta[:total_count] = total
        meta[:total_pages] = (total.to_f / limit).ceil
      end
    end
  end
end
