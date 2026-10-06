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
        @resource = build_resource
        write_resource!(@resource, resource_input)
        render_resource(@resource, status: :created)
      end

      # PUT /cars/:id replaces; PATCH /cars/:id changes only what was sent
      def update
        write_resource!(resource, resource_input, partial: request.patch?)
        render_resource(resource)
      end

      # DELETE /cars/:id
      def destroy
        destroy_resource!(resource)
        head :no_content
      end
    end
  end
end
