# frozen_string_literal: true

TestRoutes = ActionDispatch::Routing::RouteSet.new
TestRoutes.draw do
  schema_api_resources :cars, bulk: true, upsert: true, search: true
  schema_api_resources :users
  schema_api_resources :notes
  schema_api_resources :atomic_cars, bulk: true
  schema_api_resources :fleet_cars, bulk: true
  schema_api_resources :garage_cars
  schema_api_resources :dealer_cars
  schema_api_resources :strict_cars
  schema_api_resources :people_cars
  schema_api_resources :owner_records, upsert: true
end
