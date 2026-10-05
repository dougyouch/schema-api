# frozen_string_literal: true

module SchemaApi
  module Actions
    # bulk_create, bulk_update and bulk_upsert. Best effort by default: each item is written
    # in its own transaction and failures are reported per item. bulk(atomic: true) makes a
    # controller all-or-nothing.
    module Bulk
      # One bulk request's mode, preloaded records, keys seen so far and results.
      # @api private
      BulkRun = Struct.new(:mode, :records, :seen, :result)

      private

      # POST /cars/bulk_create; made public by bulk
      def bulk_create
        run_bulk(:create)
      end

      # PUT or PATCH /cars/bulk_update; made public by bulk
      def bulk_update
        run_bulk(:update)
      end

      # PUT or PATCH /cars/bulk_upsert; made public by bulk with upsert_key
      def bulk_upsert
        run_bulk(:upsert)
      end

      def run_bulk(mode)
        inputs = resource_inputs
        result = BulkResult.new(inputs.size)
        run = BulkRun.new(mode, preload_bulk_records(mode, inputs), {}, result)
        schema_api.bulk.atomic ? write_bulk_atomic(run, inputs) : write_bulk(run, inputs)
        render_bulk(result)
      end

      def write_bulk(run, inputs)
        inputs.each_with_index { |input, index| write_bulk_item(run, input, index) }
      end

      # every item in one transaction; any failure rolls them all back
      def write_bulk_atomic(run, inputs)
        contexts = []
        resource_model.transaction(requires_new: true) do
          contexts = deferring_commits { write_bulk(run, inputs) }
          raise ActiveRecord::Rollback if run.result.any_failed?
        end
        return run.result.roll_back! if run.result.any_failed?

        contexts.each { |context| schema_api.callbacks.run(self, :commit, context) { nil } }
      end

      def write_bulk_item(run, input, index)
        record = bulk_record(run, input)
        creating = record.new_record?
        write_resource!(record, input, partial: request.patch? && !creating)
        run.result.succeed(index, record, creating ? :created : :updated)
      rescue SchemaApi::Error => e
        log_error_response(e)
        run.result.fail(index, e)
      end

      def preload_bulk_records(mode, inputs)
        case mode
        when :update then scoped_resources.where(bulk_key_field.model_name => inputs.map { |input| bulk_key(input) }.compact.uniq)
                                          .index_by { |record| record.public_send(bulk_key_field.model_name) }
        when :upsert then find_resources_for_upsert(inputs)
        else {}
        end
      end

      def bulk_record(run, input)
        return build_resource if run.mode == :create

        key = run.mode == :update ? bulk_key(input) : upsert_key_values(input)
        check_bulk_key!(run.mode, input, key, run.seen)
        run.records[key] || (run.mode == :upsert ? build_resource : raise_bulk_not_found(key))
      end

      def check_bulk_key!(mode, input, key, seen)
        mode == :upsert ? check_upsert_key!(input) : check_bulk_key_sent!(key)
        if seen.key?(key)
          raise InvalidData.new("#{resource_label} has invalid data",
                                details: [{ field: nil, error: 'duplicate_key',
                                            message: 'The same key appears more than once in this request' }])
        end

        seen[key] = true
      end

      def check_bulk_key_sent!(key)
        return unless key.nil?

        field = bulk_key_field.name.to_s
        raise InvalidData.new("#{resource_label} has invalid data",
                              details: [{ field: field, error: 'required', message: "#{field.humanize} is required to update" }])
      end

      def raise_bulk_not_found(key)
        raise NotFound.new("#{resource_label} #{key} not found",
                           details: [{ field: bulk_key_field.name.to_s, error: 'not_found',
                                       message: "#{resource_label} #{key} not found" }])
      end

      def bulk_key_field
        resource_schema_class.api_field(schema_api.bulk.key)
      end

      def bulk_key(input)
        input.public_send(bulk_key_field.getter)
      end

      def render_bulk(result)
        render json: {
          schema_api.collection_root => result.records.map { |record| record && resource_json(record) },
          errors: result.errors.map { |index, error| { index: index, error: ErrorSchema.from_error(error).to_response[:error] } },
          meta: result.meta
        }, status: bulk_response_status(result)
      end

      # @param result [BulkResult]
      # @return [Symbol, Integer] 200 by default; bulk(status:) or an override changes it
      def bulk_response_status(result)
        return 422 if schema_api.bulk.atomic && result.any_failed?

        status = schema_api.bulk.status
        status.is_a?(Proc) ? instance_exec(result, &status) : status
      end
    end
  end
end
