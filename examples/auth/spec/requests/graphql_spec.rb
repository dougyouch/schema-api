# frozen_string_literal: true

RSpec.describe 'GraphQL' do
  let!(:acme) { create_organization(name: 'Acme') }
  let!(:globex) { create_organization(name: 'Globex') }
  let!(:ada) { create_user(name: 'Ada') }
  let!(:grace) { create_user(name: 'Grace') }
  let!(:linus) { create_user(name: 'Linus') }

  before do
    ada.affiliations.create!(organization: acme)
    grace.affiliations.create!(organization: acme)
    linus.affiliations.create!(organization: globex)
  end

  def graphql(query, headers:, variables: {})
    post '/graphql', headers: headers, params: body(query: query, variables: variables)
  end

  def names(field = 'users')
    json.dig('data', field, 'nodes').map { |node| node['name'] }
  end

  it 'lists users with their nested affiliations, as an application sees them' do
    graphql(<<~GRAPHQL, headers: app_headers)
      { users { nodes { name affiliations { organization { name slug } } } meta { next_cursor } } }
    GRAPHQL

    expect(response).to have_http_status(:ok)
    expect(json.dig('data', 'users', 'nodes')).to include(
      { 'name' => 'Ada', 'affiliations' => [{ 'organization' => { 'name' => 'Acme', 'slug' => 'acme' } }] }
    )
    expect(names).to eq(%w[Ada Grace Linus])
  end

  it "scopes a user's queries the same way REST does" do
    headers = user_headers(ada)
    graphql(<<~GRAPHQL, headers: headers, variables: { linus: linus.id.to_s })
      query($linus: ID!) {
        users { nodes { name } }
        organizations { nodes { name member_count } }
        user(id: $linus) { name }
      }
    GRAPHQL

    expect(names).to eq(%w[Ada Grace])
    expect(json.dig('data', 'organizations', 'nodes')).to eq([{ 'name' => 'Acme', 'member_count' => 2 }])
    expect(json.dig('data', 'user')).to be_nil
    expect(json['errors']).to contain_exactly(include('path' => ['user'], 'message' => 'User not found'))
  end

  it 'filters and sorts with the declared search' do
    graphql('{ users(filter: { name: { contains: "a" } }, sort: "-name") { nodes { name } } }', headers: app_headers)

    expect(names).to eq(%w[Grace Ada])
  end

  it 'requires a token, reported per field with the 401 code' do
    graphql('{ users { nodes { name } } }', headers: { 'Content-Type' => 'application/json' })

    expect(response).to have_http_status(:ok)
    expect(json['data']).to eq('users' => nil)
    expect(json['errors'].first['extensions']).to eq('code' => 'unauthorized', 'status' => 401, 'details' => [])
  end

  it 'never exposes write-only fields' do
    graphql('{ users { nodes { password } } }', headers: app_headers)

    expect(json['errors'].first['message']).to eq("Field 'password' doesn't exist on type 'User'")
  end

  it "lists the caller's sessions, which only users have" do
    headers = user_headers(ada)
    graphql('{ sessions { nodes { user { name } } } }', headers: headers)

    expect(json.dig('data', 'sessions', 'nodes')).to eq([{ 'user' => { 'name' => 'Ada' } }])
  end
end
