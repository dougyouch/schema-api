# frozen_string_literal: true

RSpec.describe 'organizations and members' do
  it 'can only be created with an application token, which is recorded' do
    post '/organizations', headers: app_headers, params: body(organization: { name: 'Acme', slug: 'acme' })

    expect(response).to have_http_status(:created)
    expect(json['organization']).to include('slug' => 'acme', 'member_count' => 0, 'application' => include('name' => 'billing'))

    user = create_user
    post '/organizations', headers: user_headers(user), params: body(organization: { name: 'Mine', slug: 'mine' })
    expect(response).to have_http_status(:forbidden)
  end

  it 'validates slugs, which can only be set on create' do
    post '/organizations', headers: app_headers, params: body(organization: { name: 'Acme', slug: 'Not A Slug' })
    expect(json['error']['details']).to eq([{ 'field' => 'slug', 'error' => 'invalid',
                                              'message' => 'Slug must be lowercase words joined by dashes' }])

    acme = create_organization
    patch "/organizations/#{acme.id}", headers: app_headers, params: body(organization: { slug: 'other' })
    expect(json['error']['details'].first['error']).to eq('create_only_attribute')
  end

  it 'upserts by slug and soft deletes' do
    put '/organizations/upsert', headers: app_headers, params: body(organization: { name: 'Acme', slug: 'acme' })
    expect(response).to have_http_status(:created)
    put '/organizations/upsert', headers: app_headers, params: body(organization: { name: 'Acme Inc', slug: 'acme' })
    expect(response).to have_http_status(:ok)

    id = json['organization']['id']
    delete "/organizations/#{id}", headers: app_headers
    get "/organizations/#{id}", headers: app_headers
    expect(response).to have_http_status(:not_found)
  end

  describe 'members' do
    let!(:acme) { create_organization }
    let!(:boss) { create_user(name: 'Boss') }
    let!(:ada) { create_user(name: 'Ada') }
    let!(:outsider) { create_user(name: 'Outsider') }

    before { boss.affiliations.create!(organization: acme) }

    it 'adds members whose manager must belong to the organization' do
      post "/organizations/#{acme.id}/members", headers: app_headers, params: body(member: {
                                                                                     user_id: ada.id, affiliation_attributes: {
                                                                                       department: 'Eng', manager_user_id: outsider.id
                                                                                     }
                                                                                   })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']['details'].first).to include('field' => 'affiliation_attributes.manager_user_id',
                                                        'error' => 'not_found')

      post "/organizations/#{acme.id}/members", headers: app_headers, params: body(member: {
                                                                                     user_id: ada.id, affiliation_attributes: {
                                                                                       department: 'Eng', manager_user_id: boss.id
                                                                                     }
                                                                                   })
      expect(response).to have_http_status(:created)
      expect(json['member']).to include('user_id' => ada.id, 'user' => include('name' => 'Ada'),
                                        'affiliation_attributes' => include('manager_user_id' => boss.id, 'manager_user' => { 'name' => 'Boss' }))
    end

    it "finds a manager's reports and filters by department" do
      ada.affiliations.create!(organization: acme).create_affiliation_attribute!(department: 'Eng', manager_user: boss)
      get "/organizations/#{acme.id}/members", headers: app_headers,
                                               params: { 'affiliation_attributes.manager_user_id' => boss.id }
      expect(json['members'].map { |m| m['user_id'] }).to eq([ada.id])

      get "/organizations/#{acme.id}/members", headers: app_headers, params: { 'affiliation_attributes.department' => 'Sales' }
      expect(json['members']).to eq([])
    end

    it 'adds members in bulk, matched by user' do
      members = [
        { user_id: boss.id, affiliation_attributes: { title: 'CEO' } },
        { user_id: ada.id }
      ]
      put "/organizations/#{acme.id}/members/bulk_upsert", headers: app_headers, params: body(members: members)

      expect(json['meta']).to eq('created' => 1, 'updated' => 1, 'failed' => 0)
      expect(boss.affiliations.first.affiliation_attribute.title).to eq('CEO')
    end

    it 'is a 404 for an organization the user is not in' do
      get "/organizations/#{acme.id}/members", headers: user_headers(outsider)
      expect(response).to have_http_status(:not_found)
    end
  end
end
