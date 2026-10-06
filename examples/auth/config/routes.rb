# frozen_string_literal: true

Rails.application.routes.draw do
  schema_api_resources :sessions, only: %i[index show create destroy]
  schema_api_resources :users, upsert: true, bulk: true, search: true
  schema_api_resources :organizations, upsert: true, bulk: true do
    schema_api_resources :members, controller: 'organization_members', upsert: true, bulk: true
  end
end
