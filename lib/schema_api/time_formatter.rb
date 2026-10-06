# frozen_string_literal: true

module SchemaApi
  # Formats times for responses.
  module TimeFormatter
    module_function

    # @param value [Time]
    # @param format [Symbol, Proc] :iso8601, :iso8601_usec, :unix, or a proc given the time
    # @return [String, Integer, Object]
    def format(value, format)
      case format
      when Proc then format.call(value)
      when :unix then value.to_i
      when :iso8601_usec then value.iso8601(6)
      else value.iso8601
      end
    end
  end
end
