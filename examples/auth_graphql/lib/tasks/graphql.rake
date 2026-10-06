# frozen_string_literal: true

namespace :graphql do
  desc 'Write the GraphQL schema to schema.graphql'
  task dump: :environment do
    File.write(Rails.root.join('schema.graphql'), GraphqlController.graphql_schema.to_definition)
    puts 'wrote schema.graphql'
  end
end
