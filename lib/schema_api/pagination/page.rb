# frozen_string_literal: true

module SchemaApi
  module Pagination
    # One page of results.
    #
    # @!attribute records
    #   @return [Array<ActiveRecord::Base>]
    # @!attribute meta
    #   @return [Hash] limit, next_cursor or page/next_page, and total_count when counted
    Page = Struct.new(:records, :meta)
  end
end
