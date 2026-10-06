# frozen_string_literal: true

RSpec.describe 'POST /graphql' do
  let!(:acme) { create_organization(name: 'Acme') }
  let!(:globex) { create_organization(name: 'Globex') }
  let!(:ada) { create_user(name: 'Ada') }
  let!(:grace) { create_user(name: 'Grace') }
  let!(:linus) { create_user(name: 'Linus') }

  before do
    ada.affiliations.create!(organization: acme).create_affiliation_attribute!(department: 'Engineering', title: 'Lead')
    grace.affiliations.create!(organization: acme).create_affiliation_attribute!(title: 'Engineer', manager_user: ada)
    linus.affiliations.create!(organization: globex)
  end

  def names(field = 'users')
    json.dig('data', field, 'nodes').map { |node| node['name'] }
  end

  it 'is the only route' do
    expect(Rails.application.routes.routes.map { |route| route.path.spec.to_s }).to eq(['/graphql(.:format)'])
  end

  it 'reads a user tree in one query, as an application' do
    graphql(<<~GRAPHQL, headers: app_headers, variables: { id: grace.id })
      query($id: ID!) {
        user(id: $id) {
          name email
          affiliations { organization { name } affiliation_attributes { title manager_user { name } } }
        }
      }
    GRAPHQL

    expect(json).to eq('data' => { 'user' => {
                         'name' => 'Grace', 'email' => 'grace@example.com',
                         'affiliations' => [{ 'organization' => { 'name' => 'Acme' },
                                              'affiliation_attributes' => { 'title' => 'Engineer',
                                                                            'manager_user' => { 'name' => 'Ada' } } }]
                       } })
  end

  it "scopes every field to what the caller's token allows" do
    graphql(<<~GRAPHQL, headers: user_headers(ada), variables: { linus: linus.id })
      query($linus: ID!) {
        users { nodes { name } }
        organizations { nodes { name member_count } }
        session(id: "current") { user { name } }
        linus: user(id: $linus) { name }
      }
    GRAPHQL

    expect(names).to eq(%w[Ada Grace])
    expect(json.dig('data', 'organizations', 'nodes')).to eq([{ 'name' => 'Acme', 'member_count' => 2 }])
    expect(json.dig('data', 'session')).to eq('user' => { 'name' => 'Ada' })
    expect(json.dig('data', 'linus')).to be_nil
    expect(json['errors']).to contain_exactly(include('path' => ['linus'], 'message' => 'User not found'))
  end

  it 'searches and pages' do
    query = <<~GRAPHQL
      query($organization: Int, $cursor: String) {
        users(filter: { affiliations_organization_id: { eq: $organization } }, sort: "-name", limit: 1, cursor: $cursor) {
          nodes { name }
          meta { next_cursor }
        }
      }
    GRAPHQL
    headers = app_headers
    graphql(query, headers: headers, variables: { organization: acme.id })
    expect(names).to eq(%w[Grace])

    cursor = json.dig('data', 'users', 'meta', 'next_cursor')
    graphql(query, headers: headers, variables: { organization: acme.id, cursor: cursor })
    expect(names).to eq(%w[Ada])
  end

  it 'reports a missing token on each field, with the 401 code' do
    graphql('{ users { nodes { name } } sessions { nodes { id } } }', headers: { 'Content-Type' => 'application/json' })

    expect(response).to have_http_status(:ok)
    expect(json['data']).to eq('users' => nil, 'sessions' => nil)
    expect(json['errors'].map { |error| error['extensions']['code'] }).to eq(%w[unauthorized unauthorized])
  end

  it 'only lets users list sessions' do
    graphql('{ sessions { nodes { id } } }', headers: app_headers)

    expect(json['errors'].first['message']).to eq('A session token is required')
  end

  it 'has no password field' do
    graphql('{ users { nodes { password } } }', headers: app_headers)

    expect(json['errors'].first['message']).to eq("Field 'password' doesn't exist on type 'User'")
  end

  it 'matches the committed schema.graphql (rails graphql:dump updates it)' do
    expect(GraphqlController.graphql_schema.to_definition).to eq(Rails.root.join('schema.graphql').read)
  end
end
