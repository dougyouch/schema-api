# frozen_string_literal: true

module SchemaApi
  module Actions
    # The search behind index, and POST /cars/search for searches sent as a JSON body.
    module Search
      private

      # POST /cars/search with { "search": { "make": "Ford", "sort": "-year" } }; made public by `search`
      def search
        render_search(input_parser('search').object)
      end

      # @param search_params [Hash] filters, sort, limit, cursor, page, count
      def render_search(search_params)
        page = search_page(search_params)
        render_resources(page.records, page.meta)
      end

      # @param search_params [Hash] filters, sort, limit, cursor, page, count
      # @return [SchemaApi::Pagination::Page]
      # @raise [InvalidData]
      def search_page(search_params)
        query = schema_api.search.parse(search_params, schema_api.pagination)
        paginate_resources(search_resources(query), query)
      end

      # @param query [SchemaApi::Search::Query]
      # @return [ActiveRecord::Relation] scoped_resources filtered and sorted
      def search_resources(query)
        query.apply(scoped_resources, self)
      end

      # @return [SchemaApi::Pagination::Page]
      def paginate_resources(scope, query)
        schema_api.pagination.paginate(scope, query)
      end
    end
  end
end
