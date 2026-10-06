# frozen_string_literal: true

module SchemaApi
  module Actions
    # index, show, create, update (PUT and PATCH) and destroy.
    module Crud
      # GET /cars: search, sort and paginate. See {Search::Definition}.
      def index
        render_search(request.query_parameters)
      end

      # GET /cars/:id
      def show
        render_resource(resource)
      end

      # POST /cars
      def create
        render_resource(create_resource!(resource_input), status: :created)
      end

      # PUT /cars/:id replaces; PATCH /cars/:id changes only what was sent
      def update
        render_resource(update_resource!(resource_input, partial: request.patch?))
      end

      # DELETE /cars/:id
      def destroy
        destroy_resource!(resource)
        head :no_content
      end

      private

      # @param input [Schema::Model]
      # @return [ActiveRecord::Base] the new record, also {#resource}
      def create_resource!(input)
        @resource = build_resource
        write_resource!(@resource, input)
      end

      # @param input [Schema::Model]
      # @param partial [Boolean] PATCH semantics
      # @return [ActiveRecord::Base] {#resource}, written
      def update_resource!(input, partial:)
        write_resource!(resource, input, partial: partial)
      end
    end
  end
end
