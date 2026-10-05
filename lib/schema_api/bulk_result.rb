# frozen_string_literal: true

module SchemaApi
  # Per-item results of a bulk request, in request order.
  class BulkResult
    # @return [Array<ActiveRecord::Base, nil>] the record for each item, nil when it failed
    attr_reader :records
    # @return [Array<Array(Integer, SchemaApi::Error)>] [index, error] for each failed item
    attr_reader :errors

    # @param size [Integer] number of items
    def initialize(size)
      @records = Array.new(size)
      @outcomes = Array.new(size)
      @errors = []
    end

    # @param index [Integer]
    # @param record [ActiveRecord::Base]
    # @param outcome [Symbol] :created or :updated
    def succeed(index, record, outcome)
      @records[index] = record
      @outcomes[index] = outcome
    end

    # @param index [Integer]
    # @param error [SchemaApi::Error]
    def fail(index, error)
      @errors << [index, error]
      @outcomes[index] = :failed
    end

    # Clears the successes after an atomic batch is rolled back.
    def roll_back!
      @records.fill(nil)
      @outcomes.map! { |outcome| outcome == :failed ? :failed : nil }
    end

    # @return [Boolean]
    def any_failed?
      @errors.any?
    end

    # @return [Boolean]
    def all_failed?
      !@records.empty? && @errors.size == @records.size
    end

    # @return [Hash] created, updated and failed counts
    def meta
      { created: @outcomes.count(:created), updated: @outcomes.count(:updated), failed: @errors.size }
    end
  end
end
