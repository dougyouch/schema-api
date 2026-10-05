# frozen_string_literal: true

module SchemaApi
  # Reads SchemaApi's options off a schema field's options hash.
  class Field
    # @return [Hash] the schema-model field options
    attr_reader :options
    # @return [Class] the schema class the field belongs to
    attr_reader :owner

    # @param options [Hash]
    # @param owner [Class]
    def initialize(options, owner)
      @options = options
      @owner = owner
    end

    # @return [Symbol]
    def name
      options[:name]
    end

    # @param schema [Schema::Model]
    # @return [Boolean] whether the input contained this field (nil included); works for associations too
    def set_in?(schema)
      schema.instance_variable_defined?(instance_variable)
    end

    # @return [Symbol] schema type, e.g. :integer or :has_many
    def type
      options[:type]
    end

    # @return [String]
    def getter
      options[:getter]
    end

    # @return [String]
    def setter
      options[:setter]
    end

    # @return [String]
    def instance_variable
      options[:instance_variable]
    end

    # @return [Boolean] true for has_one, has_many and belongs_to
    def association?
      options[:association] == true
    end

    # @return [Boolean]
    def has_many?
      association? && type == :has_many
    end

    # @return [Boolean] true for a belongs_to reference
    def belongs_to?
      options[:belongs_to] == true
    end

    # @return [Hash, nil] belongs_to settings: key:, key_field:, scope:, input:, on_put_missing:, render_key:
    def reference
      options[:reference]
    end

    # @return [Symbol, nil] the belongs_to this field is the key of
    def reference_for
      options[:reference_for]
    end

    # @return [Boolean]
    def reference_key?
      !reference_for.nil?
    end

    # @return [Hash, nil] { association:, field: } for a list of values stored as child rows
    def values_of
      options[:values_of]
    end

    # @return [Boolean] true for the _destroy flag on has_many items
    def destroy_flag?
      options[:destroy_flag] == true
    end

    # @return [Boolean] true for a model_attribute still waiting for its type
    def pending?
      type == ResourceSchema::PENDING_TYPE
    end

    # @return [Hash] the options model_attribute was called with
    def declared_options
      options[:declared_options] || {}
    end

    # @param creating [Boolean]
    # @return [Boolean] whether a request may write this field
    def input?(creating)
      return true if options[:input] == true || write_only?

      options[:input] == :create && creating
    end

    # @return [Boolean] whether any request may write this field
    def writable?
      input?(true)
    end

    # @return [Boolean]
    def create_only?
      options[:input] == :create
    end

    # @return [Boolean]
    def write_only?
      options[:write_only] == true
    end

    # @return [Boolean] whether the field is rendered; render: false hides a field that isn't
    #   write-only, e.g. a belongs_to key without render_key:
    def output?
      !write_only? && !destroy_flag? && options[:render] != false
    end

    # @return [Boolean, Symbol] true or :required for an optimistic lock field
    def lock
      options[:lock]
    end

    # @return [Boolean]
    def lock?
      lock ? true : false
    end

    # @return [Symbol, nil] the model attribute or association; nil for model: false and computed (value:) fields
    def model_name
      return (value_proc ? nil : name) unless options.key?(:model)

      options[:model] || nil
    end

    # @return [Symbol, String, nil] the model column holding the value: the foreign key for a
    #   belongs_to key field (key: :id), otherwise {#model_name}
    def column
      options[:column] || model_name
    end

    # @return [Symbol, Proc, nil] controller method or proc the server sets this field from (set:)
    def server_value
      options[:set]
    end

    # @return [Symbol] :create to set only on create, :save to set on every save that changes the record
    def set_on
      options[:on] || :save
    end

    # @return [Proc, nil] computes the output value from the record
    def value_proc
      options[:value]
    end

    # @return [Symbol, Proc] time format
    def format
      options[:format] || (lock? ? :iso8601_usec : :iso8601)
    end

    # @return [Array<Symbol>] fields a has_many item is matched to an existing child by
    def match_keys
      Array(options[:match_key] || :id).map(&:to_sym)
    end

    # @return [Symbol] :destroy, :delete, :nullify or :error
    def on_remove
      options[:on_remove] || :destroy
    end

    # @return [Symbol] :merge or :replace, how PATCH treats a has_many list
    def patch_mode
      options[:patch] || :merge
    end

    # @return [Boolean] whether eager loading includes this association
    def includes?
      options[:includes] != false
    end

    # @return [Symbol, Array, Hash, nil] what a computed (value:) field needs loaded, from includes:
    def value_includes
      options[:includes] if value_proc
    end

    # @return [Boolean] a plain value copied to and from the model by the mappings
    def scalar?
      !association? && !reference_key? && values_of.nil? && !destroy_flag?
    end

    # @return [Boolean] rendered by the output mapping
    def output_mapped?
      scalar? && output? && (value_proc || model_name) ? true : false
    end

    # @return [Boolean] written to the model by the input mappings
    def input_mapped?
      scalar? && writable? && !model_name.nil? && value_proc.nil?
    end

    # @return [Class] the nested schema class of an association
    def nested_class
      owner.const_get(options[:class_name])
    end

    # @return [Symbol] :association, :json or :reference
    def backing
      nested_class.api_backing
    end
  end
end
