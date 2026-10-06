# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Runs a SchemaApi controller for one GraphQL field, the way Rails would run the matching
    # REST action: a new controller for the request, its callbacks for that action
    # (before_action authorization, around_action), then its own search, lookup, write
    # pipeline and resource_json. Anything a controller overrides applies to GraphQL too.
    class ControllerRunner
      # @param controller_class [Class] a SchemaApi controller
      # @param request [ActionDispatch::Request] the GraphQL request
      def initialize(controller_class, request)
        @controller_class = controller_class
        @request = request
      end

      # What index returns.
      # @param search_params [Hash] filters, sort, limit, cursor, page, count
      # @return [Hash] nodes: rendered resources, meta: the page's meta
      def list(search_params)
        run('index') do |controller|
          page = controller.send(:search_page, search_params)
          { nodes: page.records.map { |record| render(controller, record) }, meta: page.meta }
        end
      end

      # What show returns.
      # @param record_id [String]
      # @return [Hash] the rendered resource
      def find(record_id)
        run('show', id: record_id) { |controller| render(controller, controller.send(:resource)) }
      end

      # What create does.
      # @param data [Hash] the input, as a request body would send it under the root key
      # @return [Hash] the rendered resource
      def create(data)
        run('create') { |controller| render(controller, controller.send(:create_resource!, input(controller, data))) }
      end

      # What PATCH does: only what's sent changes.
      # @param record_id [String]
      # @param data [Hash]
      # @return [Hash]
      def update(record_id, data)
        run('update', id: record_id) do |controller|
          render(controller, controller.send(:update_resource!, input(controller, data), partial: true))
        end
      end

      # What PATCH /upsert does: merges into the record matching the upsert key, or creates it.
      # @param data [Hash]
      # @return [Hash]
      def upsert(data)
        run('upsert') do |controller|
          record, _created = controller.send(:upsert_resource!, input(controller, data), partial: true)
          render(controller, record)
        end
      end

      # What destroy does.
      # @param record_id [String]
      # @return [Hash] the resource as it was before it was destroyed
      def destroy(record_id)
        run('destroy', id: record_id) do |controller|
          record = controller.send(:resource)
          rendered = render(controller, record)
          controller.send(:destroy_resource!, record)
          rendered
        end
      end

      private

      def input(controller, data)
        controller.send(:build_input, data)
      end

      def render(controller, record)
        controller.send(:resource_json, record)
      end

      # @raise [NotFound] for ActiveRecord::RecordNotFound anywhere in the action, as REST's rescue_from does
      def run(action, params = {})
        controller_instance = @request.controller_instance
        controller = build_controller(action, params)
        ran = false
        result = nil
        controller.run_callbacks(:process_action) do
          ran = true
          result = yield controller
        end
        raise halted(controller, action) unless ran

        result
      rescue ActiveRecord::RecordNotFound
        raise NotFound, "#{@controller_class.schema_api_definition.model.model_name.human} not found"
      ensure
        @request.controller_instance = controller_instance
      end

      def build_controller(action, params)
        controller = @controller_class.new
        controller.set_request!(@request)
        controller.set_response!(@controller_class.make_response!(@request))
        controller.action_name = action
        controller.params = params
        controller
      end

      # a callback that rendered instead of raising stops the action, as it would in Rails
      def halted(controller, action)
        Forbidden.new("#{@controller_class.name}##{action} stopped the request (status #{controller.response.status})")
      end
    end
  end
end
