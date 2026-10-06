# frozen_string_literal: true

module SchemaApi
  # Matches has_many items to existing children by the association's key fields.
  class ChildMatcher
    # @param field [Field] the has_many field
    # @param existing [Array] existing children: records, or schemas with reader: :schema
    # @param reader [Symbol] :record reads keys through model attributes, :schema through schema getters
    def initialize(field, existing, reader: :record)
      @key_fields = field.match_keys.map { |key| field.nested_class.api_field(key) }
      @reader = reader
      @index = existing.index_by { |child| existing_key(child) }
    end

    # @param item [Schema::Model]
    # @return [Array, nil] the item's key values, nil when none were sent
    def key_for(item)
      values = @key_fields.map { |field| item.public_send(field.getter) }
      values.all?(&:nil?) ? nil : values
    end

    # @param item [Schema::Model]
    # @return [Object, nil] the matching existing child
    def find(item)
      key = key_for(item)
      key && @index[key]
    end

    # @return [Boolean] matched by id, so an unknown key is an error rather than a new child
    def primary_key?
      @key_fields.map(&:name) == [:id]
    end

    private

    def existing_key(child)
      @key_fields.map do |field|
        @reader == :schema ? child.public_send(field.getter) : child.public_send(field.column)
      end
    end
  end
end
