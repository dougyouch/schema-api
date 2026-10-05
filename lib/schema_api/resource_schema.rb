# frozen_string_literal: true

module SchemaApi
  # Mixed into schema classes (and, through schema_include, every nested class) to add
  # model_attribute, belongs_to and the options SchemaApi reads: input:, write_only:,
  # lock:, model:, value:, format:, key:, on_remove:, patch:, values_of:.
  module ResourceSchema
    autoload :ClassMethods, 'schema_api/resource_schema/class_methods'

    # placeholder type for a model_attribute until the schema is finalized
    PENDING_TYPE = :pending_model_type

    # @api private
    def self.included(base)
      base.extend ClassMethods
      # schema_include includes the module again, which calls this hook again
      base.schema_include(self) unless base.schema_config[:schema_includes].include?(self)
    end

    # Setting a model_attribute before finalize has no type to parse with.
    # @raise [NotFinalizedError]
    def parse_pending_model_type(field_name, _parsing_errors, _value)
      raise NotFinalizedError,
            "#{self.class.name}##{field_name} is a model_attribute; finalize the schema before using it " \
            '(SchemaApi.finalize_all! or the controller does it on the first request)'
    end
  end
end
