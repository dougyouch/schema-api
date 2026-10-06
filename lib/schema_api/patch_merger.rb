# frozen_string_literal: true

module SchemaApi
  # Builds what a PATCH would leave behind, for validation: the current record's schema
  # with the patch laid over it. Nested lists hold only the items that were sent, in
  # request order, so validation errors keep the request's paths.
  class PatchMerger
    # @param current [Schema::Model] the record as presented
    # @param patch [Schema::Model] the parsed PATCH input
    # @return [Schema::Model] a new schema; neither argument is changed
    def merge(current, patch)
      merged = current.deep_dup
      patch.class.api_fields.each do |field|
        next unless field.set_in?(patch)
        next if field.belongs_to?

        value = merged_value(field, current.public_send(field.getter), patch.public_send(field.getter))
        merged.instance_variable_set(field.instance_variable, value)
      end
      merged
    end

    private

    def merged_value(field, current, value)
      return value if value.nil? || !field.association?
      return merge_list(field, current || [], value) if field.has_many?

      current ? merge(current, value) : value
    end

    # JSON lists and patch: :replace lists replace the stored list; other lists merge by key
    def merge_list(field, current, items)
      return items if field.backing == :json || field.patch_mode == :replace

      matcher = ChildMatcher.new(field, current, reader: :schema)
      items.map do |item|
        match = item && matcher.find(item)
        match ? merge(match, item) : item
      end
    end
  end
end
