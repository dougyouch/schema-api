# frozen_string_literal: true

RSpec.describe 'user roles and authorization' do
  let!(:read_cars) { permission('cars', 'read') }
  let!(:write_cars) { permission('cars', 'write') }
  let!(:viewer) { role('viewer', read_cars) }
  let!(:editor) { role('editor', read_cars, write_cars) }

  it 'grants a role in an organization, recording who did it' do
    post '/user_roles', headers: headers(user_id: 9),
                        params: body(user_role: { organization_id: 1, user_id: 2, role_id: editor.id, creator_id: 666 })

    expect(response).to have_http_status(:created)
    expect(json['user_role']).to include('organization_id' => 1, 'user_id' => 2, 'role_id' => editor.id, 'role' => { 'name' => 'editor' },
                                         'creator_id' => 9, 'updated_by_user_id' => 9)
  end

  it 'records who changed it last' do
    user_role = grant(viewer, organization_id: 1, user_id: 2)
    patch "/user_roles/#{user_role.id}", headers: headers(user_id: 7), params: body(user_role: { role_id: editor.id })

    expect(user_role.reload).to have_attributes(role_id: editor.id, creator_id: RolesHelpers::ADMIN_ID, updated_by_user_id: 7)
  end

  it "doesn't let users change their own roles" do
    post '/user_roles', headers: headers(user_id: 2),
                        params: body(user_role: { organization_id: 1, user_id: 2, role_id: editor.id })

    expect(json['error']['details']).to eq([{ 'field' => 'user_id', 'error' => 'self_grant',
                                              'message' => "You can't change your own roles" }])
  end

  it 'assigns roles in bulk, matched by organization, user and role' do
    grant(viewer, organization_id: 1, user_id: 2)
    user_roles = [
      { organization_id: 1, user_id: 2, role_id: viewer.id },
      { organization_id: 1, user_id: 3, role_id: editor.id },
      { organization_id: 1, user_id: 4, role_id: 0 }
    ]
    put '/user_roles/bulk_upsert', headers: headers, params: body(user_roles: user_roles)

    expect(json['meta']).to eq('created' => 1, 'updated' => 1, 'failed' => 1)
    expect(json['errors'].first['error']['details'].first).to include('field' => 'role_id', 'error' => 'not_found')
  end

  it "lists a user's permissions in an organization" do
    grant(viewer, organization_id: 1, user_id: 2)
    grant(editor, organization_id: 5, user_id: 2)
    get '/organizations/1/users/2/permissions'

    expect(json['permissions'].map { |p| p['action'] }).to eq(%w[read])
    expect(json['meta']).to include('total_count' => 1)
  end

  it 'answers whether a user may do something, and why' do
    grant(viewer, organization_id: 1, user_id: 2)
    grant(editor, organization_id: 1, user_id: 2)
    get '/authorize', params: { organization_id: 1, user_id: 2, resource: 'cars', action: 'write' }
    expect(json['authorization']).to include('allowed' => true, 'roles' => %w[editor])

    get '/authorize', params: { organization_id: 5, user_id: 2, resource: 'cars', action: 'read' }
    expect(json['authorization']).to include('allowed' => false, 'roles' => [])
  end

  it 'reports a bad authorization query in the standard format' do
    get '/authorize', params: { organization_id: 'one', user_id: 2 }

    expect(response).to have_http_status(:bad_request)
    expect(json['error']['details'].map { |d| [d['field'], d['error']] }).to contain_exactly(
      %w[organization_id invalid], %w[organization_id blank], %w[resource blank], %w[action blank]
    )
  end
end
