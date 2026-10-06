# frozen_string_literal: true

module SchemaApi
  # Adds schema_api_resources to the Rails router: resources plus the collection routes for
  # the add-ons a controller enables.
  #
  #   schema_api_resources :cars, bulk: true, upsert: true, search: true
  module Routing
    # @param names [Array<Symbol>]
    # @param bulk [Boolean] bulk_create, bulk_update, bulk_upsert
    # @param upsert [Boolean] upsert
    # @param search [Boolean] POST search
    # @param options [Hash] passed to resources
    def schema_api_resources(*names, bulk: false, upsert: false, search: false, **options, &block)
      add_ons = { bulk: bulk, upsert: upsert, search: search }
      resources(*names, **options) do
        collection { schema_api_collection_routes(**add_ons) }
        instance_eval(&block) if block
      end
    end

    private

    def schema_api_collection_routes(bulk:, upsert:, search:)
      post :search if search
      if upsert
        put :upsert
        patch :upsert
      end
      return unless bulk

      post :bulk_create
      %i[bulk_update bulk_upsert].each do |action|
        put action
        patch action
      end
    end
  end
end
