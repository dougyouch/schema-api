# frozen_string_literal: true

module SchemaApi
  # Collects error details ({ field:, error:, message: }) before they're raised together.
  class ErrorList
    include Enumerable

    def initialize
      @details = []
    end

    # @param field [String, Symbol, nil] dotted path, e.g. "affiliations[0].tenant_id"
    # @param error [String, Symbol] machine code, e.g. "blank"
    # @param message [String, nil] readable message; built from the field and code when nil
    # @return [self]
    def add(field, error, message = nil)
      field = field&.to_s
      @details << { field: field, error: error.to_s, message: message || default_message(field, error) }
      self
    end

    # @param details [Array<Hash>]
    # @return [self]
    def concat(details)
      @details.concat(details.to_a)
      self
    end

    # @yield [Hash]
    def each(&)
      @details.each(&)
    end

    # @return [Boolean]
    def empty?
      @details.empty?
    end

    # @return [Array<Hash>]
    def to_a
      @details.dup
    end

    private

    def default_message(field, error)
      name = field ? field.split('.').last.sub(/\[\d+\]\z/, '').humanize : 'Value'
      "#{name} is #{error.to_s.humanize(capitalize: false)}"
    end
  end
end
