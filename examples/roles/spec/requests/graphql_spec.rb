# frozen_string_literal: true

RSpec.describe 'GraphQL' do
  let!(:read_cars) { permission('cars', 'read') }
  let!(:write_cars) { permission('cars', 'write') }
  let!(:viewer) { role('viewer', read_cars) }
  let!(:editor) { role('editor', read_cars, write_cars) }

  before do
    grant(viewer, organization_id: 1, user_id: 2)
    grant(editor, organization_id: 1, user_id: 3)
    grant(viewer, organization_id: 2, user_id: 3)
  end

  def graphql(query, variables = {})
    post '/graphql', headers: { 'Content-Type' => 'application/json' }, params: body(query: query, variables: variables)
  end

  def data
    json['data']
  end

  it 'reads roles with their computed permissions, without X-User-Id' do
    graphql('{ roles { nodes { name permission_ids permissions } meta { total_count } } }')

    expect(response).to have_http_status(:ok)
    expect(data['roles']['meta']).to eq('total_count' => 2)
    expect(data['roles']['nodes'].first).to include('name' => 'editor', 'permission_ids' => [read_cars.id, write_cars.id])
    expect(data['roles']['nodes'].first['permissions'].map { |p| p['action'] }).to eq(%w[read write])
  end

  it "answers several questions in one request: a user's roles and the permission catalog" do
    graphql(<<~GRAPHQL, { user: 3 })
      query($user: Int) {
        user_roles(filter: { user_id: { eq: $user } }) { nodes { organization_id role { name } } }
        permissions(filter: { action: { in: ["write"] } }) { nodes { resource action } }
      }
    GRAPHQL

    expect(data['user_roles']['nodes']).to contain_exactly(
      { 'organization_id' => 1, 'role' => { 'name' => 'editor' } },
      { 'organization_id' => 2, 'role' => { 'name' => 'viewer' } }
    )
    expect(data['permissions']['nodes']).to eq([{ 'resource' => 'cars', 'action' => 'write' }])
  end

  it 'uses the custom search filter, typed as declared' do
    graphql('{ roles(filter: { permission: { eq: "cars:write" } }) { nodes { name } } }')

    expect(data['roles']['nodes']).to eq([{ 'name' => 'editor' }])
  end

  it 'finds one record, and reports one that is missing' do
    graphql('query($id: ID!) { role(id: $id) { name } permission(id: 0) { name } }', { id: viewer.id })

    expect(data).to eq('role' => { 'name' => 'viewer' }, 'permission' => nil)
    expect(json['errors'].first['extensions']).to include('code' => 'not_found', 'status' => 404)
  end
end
