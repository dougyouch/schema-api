# frozen_string_literal: true

module SchemaApi
  module ResourceSchema
    # Class methods for schema classes.
    module ClassMethods
      # @return [Class, nil] the ActiveRecord model behind this schema, set by finalize
      attr_accessor :schema_model
      # @return [Symbol, nil] what backs a nested schema: :association, :json or :reference
      attr_accessor :api_backing
      # @return [MappingBuilder::Mappings, nil] compiled mappings, set by finalize
      attr_accessor :api_mappings

      # Declares an attribute typed from the model's column.
      #
      # @example
      #   model_attribute :created_at                # :time, rendered as ISO 8601
      #   model_attribute :name, input: true
      #   model_attribute :email, model: :email_address
      #   model_attribute :code, :string             # explicit type, no column lookup
      #
      # @param name [Symbol]
      # @param type [Symbol, nil] skips the column lookup when given
      # @param options [Hash] attribute options
      # @return [void]
      def model_attribute(name, type = nil, **options)
        return attribute(name, type, options.merge(model_attribute: true)) if type

        attribute(name, PENDING_TYPE, options.merge(model_attribute: true, declared_options: options))
      end

      # Declares several model attributes with the same options.
      # @example
      #   model_attributes :name, :email, input: true
      # @param names [Array<Symbol>]
      # @param options [Hash] attribute options
      # @return [void]
      def model_attributes(*names, **options)
        names.each { |name| model_attribute(name, **options) }
      end

      # Declares created_at and updated_at, with updated_at as the optimistic lock.
      # @param lock [Boolean, Symbol] updated_at's lock: option; false for none
      # @return [void]
      def timestamps(lock: true)
        model_attribute :created_at
        lock ? model_attribute(:updated_at, lock: lock) : model_attribute(:updated_at)
      end

      # Declares a referenced (shared) record. It is rendered as a nested object and chosen by
      # key: the client sends `<name>_id` (or `<name>_<key>`), never the nested object.
      #
      # @param name [Symbol]
      # @param input [Boolean] accept the key as input
      # @param scope [Symbol, Proc, nil] controller method or lambda the key is looked up in;
      #   :all for the model's whole table. Required with input: true.
      # @param key [Symbol] unique field on the referenced model
      # @param render_key [Boolean] also render the key
      # @param on_put_missing [Symbol] :keep or :nullify when PUT doesn't send the key
      # @param options [Hash] has_one options, e.g. model:; set: and on: go to the key field, so the
      #   server can fill the reference (set: returns the key value)
      # @yield attribute declarations for the nested object
      # @return [Class] the nested schema class
      def belongs_to(name, input: false, scope: nil, key: :id, render_key: false, on_put_missing: :keep, **options, &)
        key_field = key.to_sym == :id ? :"#{name}_id" : :"#{name}_#{key}"
        server = options.extract!(:set, :on)
        reference = { key: key.to_sym, key_field: key_field, scope: scope, input: input,
                      on_put_missing: on_put_missing, render_key: render_key }
        nested = has_one(name, options.merge(belongs_to: true, reference: reference), &)
        key_options = { input: input, render: render_key, reference_for: name, model: false }.merge(server)
        attribute(key_field, PENDING_TYPE, key_options.merge(model_attribute: true, declared_options: key_options))
        nested
      end

      # schema-model uses :key for the field's data key, so has_many's match key is stored as :match_key
      # @api private
      def has_many(name, options = {}, &)
        super(name, rename_match_key(options), &)
      end

      # @api private
      def has_one(name, options = {}, &)
        super(name, rename_match_key(options), &)
      end

      # @return [Array<Field>] fields, aliases excluded
      def api_fields
        return @api_fields ||= build_api_fields if finalized?

        build_api_fields
      end

      # @param name [Symbol]
      # @return [Field, nil]
      def api_field(name)
        api_fields.find { |field| field.name == name.to_sym }
      end

      # @return [Boolean]
      def finalized?
        @finalized == true
      end

      # @api private
      def mark_finalized!
        @api_fields = nil
        @finalized = true
      end

      private

      def build_api_fields
        schema.each_value.reject { |options| options[:alias_of] }.map { |options| Field.new(options, self) }
      end

      def rename_match_key(options)
        return options unless options.key?(:key)

        options = options.dup
        options[:match_key] = options.delete(:key)
        options
      end
    end
  end
end
