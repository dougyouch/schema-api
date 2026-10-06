# frozen_string_literal: true

module SchemaApi
  # Turns a schema tree into the response hash: every rendered field, nils included so the
  # shape never changes, write-only fields left out, and times, dates and decimals formatted.
  class Serializer
    # @param schema [Schema::Model]
    # @return [Hash{Symbol => Object}]
    def serialize(schema)
      schema.class.api_fields.each_with_object({}) do |field, hash|
        next unless field.output?

        hash[field.name] = serialize_value(field, schema.public_send(field.getter))
      end
    end

    private

    def serialize_value(field, value)
      case value
      when nil then nil
      when ::Schema::Model then serialize(value)
      when Array then value.map { |element| serialize_value(field, element) }
      else format_value(field, value)
      end
    end

    def format_value(field, value)
      case value
      when Time, DateTime then TimeFormatter.format(value, field.format)
      when Date then value.iso8601
      when BigDecimal then value.to_s('F')
      else value
      end
    end
  end
end
