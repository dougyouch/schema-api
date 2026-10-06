# frozen_string_literal: true

module SchemaApi
  # Compares a value from a request with a stored one, e.g. for lock and create-only checks.
  module ValueComparer
    module_function

    # Times compare exactly (as rationals) whatever their class or zone.
    # @return [Boolean]
    def same?(left, right)
      return left.to_r == right.to_r if time?(left) && time?(right)

      left == right
    end

    # @api private
    def time?(value)
      value.is_a?(Time) || value.is_a?(DateTime) || value.is_a?(ActiveSupport::TimeWithZone)
    end
  end
end
