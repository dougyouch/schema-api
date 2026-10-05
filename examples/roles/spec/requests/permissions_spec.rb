# frozen_string_literal: true

RSpec.describe 'permissions' do
  it 'lets a service register its catalog with bulk_upsert, matched by resource and action' do
    permission('cars', 'read')
    permissions = [
      { resource: 'cars', action: 'read', name: 'View cars' },
      { resource: 'cars', action: 'write', name: 'Edit cars' },
      { resource: 'Cars!', action: 'delete', name: 'Bad' }
    ]
    put '/permissions/bulk_upsert', headers: headers, params: body(permissions: permissions)

    expect(json['meta']).to eq('created' => 1, 'updated' => 1, 'failed' => 1)
    expect(json['errors'].first).to include('index' => 2)
    expect(json['errors'].first['error']['details']).to eq([{ 'field' => 'resource', 'error' => 'invalid',
                                                              'message' => 'Resource must be snake_case' }])
    expect(RolesDB::Permission.order(:action).pluck(:action, :name)).to eq([['read', 'View cars'], ['write', 'Edit cars']])
  end

  it 'filters and sorts the catalog' do
    permission('cars', 'write')
    permission('cars', 'read')
    permission('trucks', 'read')
    get '/permissions', params: { resource: { in: 'cars' } }

    expect(json['permissions'].map { |p| p['action'] }).to eq(%w[read write])
    expect(json['meta']).to include('total_count' => 2)
  end

  it 'requires an acting user to change anything' do
    post '/permissions', params: body(permission: { resource: 'cars', action: 'read', name: 'x' }),
                         headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:forbidden)
    expect(json['error']['message']).to eq('X-User-Id is required to make changes')
  end
end
