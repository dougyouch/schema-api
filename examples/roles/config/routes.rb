# frozen_string_literal: true

Rails.application.routes.draw do
  schema_api_resources :roles, upsert: true, bulk: true
  schema_api_resources :permissions, upsert: true, bulk: true
  schema_api_resources :user_roles, upsert: true, bulk: true
  resources :organizations, only: [] do
    resources :users, only: [] do
      resources :permissions, only: :index, controller: 'user_permissions'
    end
  end
  get 'authorize', to: 'authorizations#show'
end
