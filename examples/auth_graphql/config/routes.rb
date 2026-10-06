# frozen_string_literal: true

# One endpoint. The resources behind it (app/graphql/resources) have no routes of their own.
Rails.application.routes.draw do
  post 'graphql', to: 'graphql#execute'
  get 'graphiql', to: 'graphiql#show' if Rails.env.development?
end
