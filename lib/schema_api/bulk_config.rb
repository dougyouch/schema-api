# frozen_string_literal: true

module SchemaApi
  # Settings for the bulk actions.
  class BulkConfig
    # @return [Integer] most items in one request
    attr_reader :max
    # @return [Boolean] all-or-nothing instead of best effort
    attr_reader :atomic
    # @return [Symbol, Integer, Proc] response status, or a proc given the {BulkResult}
    attr_reader :status
    # @return [Symbol] schema field bulk_update matches records by
    attr_reader :key

    # @param max [Integer]
    # @param atomic [Boolean]
    # @param status [Symbol, Integer, Proc]
    # @param key [Symbol]
    def initialize(max: 100, atomic: false, status: :ok, key: :id)
      @max = max
      @atomic = atomic
      @status = status
      @key = key
    end
  end
end
