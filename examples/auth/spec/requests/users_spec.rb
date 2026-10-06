# frozen_string_literal: true

RSpec.describe 'users' do
  let!(:acme) { create_organization }

  describe 'as an application' do
    it 'creates a user with affiliations, hashing the password' do
      post '/users', headers: app_headers, params: body(user: {
                                                          name: 'Ada', email: 'Ada@Example.com', password: 'secret-password',
                                                          affiliations: [{ organization_id: acme.id, affiliation_attributes: { department: 'Eng', title: 'Lead' } }]
                                                        })

      expect(response).to have_http_status(:created)
      user = AuthDB::User.find(json['user']['id'])
      expect(user.authenticate('secret-password')).to eq(user)
      expect(json['user']).to include('email' => 'ada@example.com')
      expect(json['user']).not_to have_key('password')
      expect(json['user']['affiliations'].first).to include(
        'organization_id' => acme.id, 'organization' => { 'name' => 'Acme', 'slug' => 'acme' },
        'affiliation_attributes' => { 'department' => 'Eng', 'title' => 'Lead', 'manager_user' => nil }
      )
    end

    it 'reports bad data and validation errors in the standard format' do
      post '/users', headers: app_headers, params: body(user: { name: '', email: 'nope', password: 'short', admin: true })
      expect(response).to have_http_status(:bad_request)
      expect(json['error']['details']).to include({ 'field' => 'admin', 'error' => 'unknown_attribute',
                                                    'message' => 'Admin is an unknown attribute' })

      post '/users', headers: app_headers, params: body(user: { name: '', email: 'nope', password: 'short' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']['details'].map do |d|
        [d['field'], d['error']]
      end).to contain_exactly(%w[name blank], %w[email invalid], %w[password too_short])
    end

    it 'imports users with bulk_upsert, matched by email' do
      existing = create_user(name: 'Ada')
      users = [
        { email: 'ada@example.com', name: 'Ada Lovelace' },
        { email: 'grace@example.com', name: 'Grace', password: 'secret-password' },
        { email: 'bad', name: 'X', password: 'secret-password' }
      ]
      put '/users/bulk_upsert', headers: app_headers, params: body(users: users)

      expect(response).to have_http_status(:ok)
      expect(json['meta']).to eq('created' => 1, 'updated' => 1, 'failed' => 1)
      expect(existing.reload.name).to eq('Ada Lovelace')
      expect(existing.authenticate('secret-password')).to eq(existing)
    end

    it 'checks that a manager exists' do
      user = create_user
      patch "/users/#{user.id}", headers: app_headers, params: body(user: {
                                                                      affiliations: [{ organization_id: acme.id, affiliation_attributes: { manager_user_id: 0 } }]
                                                                    })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']['details']).to eq([{ 'field' => 'affiliations[0].affiliation_attributes.manager_user_id', 'error' => 'not_found',
                                                'message' => 'Manager user 0 does not exist' }])
    end

    it 'soft deletes, ending sessions' do
      user = create_user
      headers = user_headers(user)
      delete "/users/#{user.id}", headers: app_headers

      expect(response).to have_http_status(:no_content)
      expect(user.reload.deleted_at).to be_present
      get '/sessions/current', headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'as a user' do
    let!(:ada) { create_user(name: 'Ada') }
    let!(:grace) { create_user(name: 'Grace') }
    let!(:stranger) { create_user(name: 'Stranger') }
    let(:headers) { user_headers(ada) }

    before do
      [ada, grace].each { |user| user.affiliations.create!(organization: acme) }
    end

    it 'sees only people in their organizations, with search and sort' do
      get '/users', headers: headers, params: { sort: '-name' }
      expect(json['users'].map { |u| u['name'] }).to eq(%w[Grace Ada])

      get '/users', headers: headers, params: { name: 'gra' }
      expect(json['users'].map { |u| u['name'] }).to eq(%w[Grace])

      get "/users/#{stranger.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'updates their own account, and changing the password ends other sessions' do
      other = user_headers(ada)
      patch "/users/#{ada.id}", headers: headers, params: body(user: { name: 'Ada L', password: 'new-password!' })

      expect(response).to have_http_status(:ok)
      expect(ada.reload).to have_attributes(name: 'Ada L')
      expect(ada.authenticate('new-password!')).to eq(ada)
      get '/sessions/current', headers: other
      expect(response).to have_http_status(:unauthorized)
      get '/sessions/current', headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'keeps the password on a PUT without one' do
      get "/users/#{ada.id}", headers: headers
      put "/users/#{ada.id}", headers: headers, params: body(user: json['user'])

      expect(response).to have_http_status(:ok)
      expect(ada.reload.authenticate('secret-password')).to eq(ada)
    end

    it "can't change someone else, create users, or change affiliations" do
      patch "/users/#{grace.id}", headers: headers, params: body(user: { name: 'X' })
      expect(response).to have_http_status(:forbidden)

      post '/users', headers: headers, params: body(user: { name: 'X', email: 'x@example.com', password: 'secret-password' })
      expect(response).to have_http_status(:forbidden)

      patch "/users/#{ada.id}", headers: headers,
                                params: body(user: { name: 'Ada L', affiliations: [{ organization_id: acme.id, _destroy: true }] })
      expect(response).to have_http_status(:forbidden)
      expect(json['error']['details']).to eq([{ 'field' => 'affiliations', 'error' => 'forbidden',
                                                'message' => 'Only applications can change affiliations' }])
      expect(ada.reload.name).to eq('Ada')
    end

    it 'treats PUT without affiliations as removing them, which only applications may do' do
      put "/users/#{ada.id}", headers: headers, params: body(user: { name: 'Ada', email: ada.email })
      expect(response).to have_http_status(:forbidden)

      patch "/users/#{ada.id}", headers: headers, params: body(user: { affiliations: [] })
      expect(response).to have_http_status(:ok)
      expect(ada.affiliations.count).to eq(1)
    end

    it 'accepts its own GET response back, affiliations included' do
      get "/users/#{ada.id}", headers: headers
      put "/users/#{ada.id}", headers: headers, params: body(user: json['user'].merge('name' => 'Ada L'))

      expect(response).to have_http_status(:ok)
      expect(ada.reload.name).to eq('Ada L')
    end

    it 'rejects a stale lock value' do
      get "/users/#{ada.id}", headers: headers
      read = json['user']
      ada.update!(name: 'Changed')
      put "/users/#{ada.id}", headers: headers, params: body(user: read.merge('name' => 'Mine'))

      expect(response).to have_http_status(:conflict)
      expect(json['error']['code']).to eq('stale_resource')
    end
  end

  it 'requires a token' do
    get '/users'
    expect(response).to have_http_status(:unauthorized)
  end
end
