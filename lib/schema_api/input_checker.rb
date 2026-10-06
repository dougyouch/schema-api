# frozen_string_literal: true

module SchemaApi
  # The checks a request passes before validation: no parsing errors anywhere in the tree,
  # a sent id that matches the record, unchanged create-only fields, and a lock value when
  # the schema requires one.
  class InputChecker
    # @param context [WriteContext]
    def initialize(context)
      @context = context
      @input = context.input
      @record = context.record
    end

    # @return [Array<Hash>]
    def details
      details = ErrorCollector.new.parsing_details(@input)
      return details if @context.creating?

      details.concat(id_mismatch_details)
      details.concat(CreateOnlyCheck.details(@input, @record, nil))
      details.concat(missing_lock_details)
    end

    private

    def id_mismatch_details
      field = @input.class.api_field(:id)
      return [] unless field && @input.id_was_set? && !@input.id.nil?
      return [] if ValueComparer.same?(@input.id, @record.public_send(field.model_name || :id))

      [{ field: 'id', error: 'id_mismatch',
         message: "Id doesn't match the #{@record.class.model_name.human.downcase} being updated" }]
    end

    def missing_lock_details
      @input.class.api_fields.select { |field| field.lock == :required }.filter_map do |field|
        next if field.set_in?(@input)

        { field: field.name.to_s, error: 'required', message: "#{field.name.to_s.humanize} is required to update" }
      end
    end
  end
end
