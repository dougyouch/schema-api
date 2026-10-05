# frozen_string_literal: true

module SchemaApi
  # Rendering resources and errors. Override any of these in a controller.
  module Rendering
    private

    # @param record [ActiveRecord::Base]
    # @param status [Symbol, Integer]
    def render_resource(record = resource, status: :ok)
      render json: { schema_api.root => resource_json(record) }, status: status
    end

    # @param records [Array<ActiveRecord::Base>]
    # @param meta [Hash]
    def render_resources(records, meta)
      render json: { schema_api.collection_root => records.map { |record| resource_json(record) }, meta: meta }
    end

    # The record as the schema renders it.
    # @param record [ActiveRecord::Base]
    # @return [Hash]
    def resource_json(record)
      Serializer.new.serialize(Presenter.new.present(record, resource_schema_class))
    end

    # Renders any {SchemaApi::Error} in the standard format, and logs why.
    # @param error [SchemaApi::Error]
    def render_error(error)
      log_error_response(error)
      render json: ErrorSchema.from_error(error).to_response, status: error.status
    end

    def render_record_not_found(_exception)
      render_error(NotFound.new("#{resource_model.model_name.human} not found"))
    end

    def log_error_response(error)
      logger&.info(
        "SchemaApi #{self.class.name}##{action_name} #{error.code}: #{error.message} #{error.details.to_json}"
      )
    end

    # @return [String] e.g. "Car"
    def resource_label
      resource_model.model_name.human
    end
  end
end
