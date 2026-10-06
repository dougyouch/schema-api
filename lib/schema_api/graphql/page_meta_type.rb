# frozen_string_literal: true

module SchemaApi
  module Graphql
    # A list's meta, the same as the REST index's: limit, then next_cursor (cursor pagination)
    # or page and next_page (offset), and total_count and total_pages when counted.
    class PageMetaType < ::GraphQL::Schema::Object
      graphql_name 'PageMeta'

      field :limit, Int, null: false, camelize: false, hash_key: :limit
      field :next_cursor, String, null: true, camelize: false, hash_key: :next_cursor
      field :page, Int, null: true, camelize: false, hash_key: :page
      field :next_page, Int, null: true, camelize: false, hash_key: :next_page
      field :total_count, Int, null: true, camelize: false, hash_key: :total_count
      field :total_pages, Int, null: true, camelize: false, hash_key: :total_pages
    end
  end
end
