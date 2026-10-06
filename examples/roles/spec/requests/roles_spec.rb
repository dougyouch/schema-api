# frozen_string_literal: true

RSpec.describe 'roles' do
  let!(:read_cars) { permission('cars', 'read') }
  let!(:write_cars) { permission('cars', 'write') }

  it 'creates a role from permission ids and renders the permissions' do
    post '/roles', headers: headers, params: body(role: { name: 'fleet_manager', permission_ids: [read_cars.id, write_cars.id] })

    expect(response).to have_http_status(:created)
    expect(json['role']['permission_ids']).to contain_exactly(read_cars.id, write_cars.id)
    expect(json['role']['permissions'].map { |p| p['action'] }).to contain_exactly('read', 'write')
  end

  it 'replaces the permission list on PATCH, since lists of values are replaced' do
    fleet = role('fleet_manager', read_cars, write_cars)
    patch "/roles/#{fleet.id}", headers: headers, params: body(role: { permission_ids: [read_cars.id] })

    expect(fleet.reload.permissions).to eq([read_cars])
  end

  it 'names permission ids that do not exist' do
    post '/roles', headers: headers, params: body(role: { name: 'x', permission_ids: [read_cars.id, 0] })

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']['details']).to eq([{ 'field' => 'permission_ids', 'error' => 'not_found',
                                              'message' => 'Permissions 0 do not exist' }])
  end

  it 'finds the roles that grant a permission' do
    role('viewer', read_cars)
    role('editor', read_cars, write_cars)
    get '/roles', params: { permission: 'cars:write' }

    expect(json['roles'].map { |r| r['name'] }).to eq(%w[editor])
  end

  it "won't delete a role that is still assigned" do
    viewer = role('viewer', read_cars)
    grant(viewer, organization_id: 1, user_id: 2)
    delete "/roles/#{viewer.id}", headers: headers

    expect(response).to have_http_status(:conflict)
    expect(json['error']['details'].first['error']).to eq('in_use')
  end
end
