# frozen_string_literal: true

module SchemaApi
  module Actions
    # PUT/PATCH /cars/upsert: update the record matching the upsert key, or create it.
    module Upsert
      private

      # made public by upsert_key
      def upsert
        record, created = upsert_resource!(resource_input, partial: request.patch?)
        render_resource(record, status: created ? :created : :ok)
      end

      # Finds by upsert key and writes. If a concurrent request created the same key first,
      # the unique index raises and the write is retried once as an update.
      # @return [Array(ActiveRecord::Base, Boolean)] the record, and whether it was created
      def upsert_resource!(input, partial:)
        check_upsert_key!(input)
        attempts = 0
        begin
          attempts += 1
          record = find_resource_for_upsert(input) || build_resource
          creating = record.new_record?
          [write_resource!(record, input, partial: partial), creating]
        rescue Conflict => e
          raise unless creating && attempts == 1

          logger&.info("SchemaApi #{self.class.name}#upsert retrying as update after conflict: #{e.message}")
          retry
        end
      end

      # @raise [InvalidData] when a key field wasn't sent
      def check_upsert_key!(input)
        missing = upsert_key_fields.select { |field| input.public_send(field.getter).nil? }
        return if missing.empty?

        details = missing.map do |field|
          { field: field.name.to_s, error: 'missing_upsert_key', message: "#{field.name.to_s.humanize} is required to upsert" }
        end
        raise InvalidData.new("#{resource_label} has invalid data", details: details)
      end
    end
  end
end
