# frozen_string_literal: true

module AuthGraphqlHelpers
  def app_headers
    { 'X-Application-Token' => AuthDB::Application.issue!('billing').last, 'Content-Type' => 'application/json' }
  end

  # logs in with the create_session mutation
  def user_headers(user, password: 'secret-password')
    graphql('mutation($session: SessionInput!) { create_session(session: $session) { token } }',
            headers: { 'Content-Type' => 'application/json' }, variables: { session: { email: user.email, password: password } })
    { 'Authorization' => "Bearer #{json.dig('data', 'create_session', 'token')}", 'Content-Type' => 'application/json' }
  end

  def create_user(name:, email: "#{name.downcase}@example.com")
    AuthDB::User.create!(name: name, email: email, password: 'secret-password')
  end

  def create_organization(name:, slug: name.downcase)
    AuthDB::Organization.create!(name: name, slug: slug)
  end

  def graphql(query, headers:, variables: {})
    post '/graphql', headers: headers, params: { query: query, variables: variables }.to_json
  end

  def json
    response.parsed_body
  end
end
