# frozen_string_literal: true

module AuthHelpers
  def application_token
    @application_token ||= AuthDB::Application.issue!('billing').last
  end

  def app_headers
    { 'X-Application-Token' => application_token, 'Content-Type' => 'application/json' }
  end

  def user_headers(user, password: 'secret-password')
    post '/sessions', params: { session: { email: user.email, password: password } }.to_json,
                      headers: { 'Content-Type' => 'application/json' }
    { 'Authorization' => "Bearer #{json.dig('session', 'token')}", 'Content-Type' => 'application/json' }
  end

  def create_user(name: 'Ada', email: "#{name.downcase}@example.com", password: 'secret-password')
    AuthDB::User.create!(name: name, email: email, password: password)
  end

  def create_organization(name: 'Acme', slug: name.downcase)
    AuthDB::Organization.create!(name: name, slug: slug)
  end

  def json
    response.parsed_body
  end

  def body(payload)
    payload.to_json
  end
end
