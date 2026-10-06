# frozen_string_literal: true

RSpec.describe 'mutations' do
  let!(:acme) { create_organization(name: 'Acme') }
  let!(:ada) { create_user(name: 'Ada') }
  let!(:grace) { create_user(name: 'Grace') }

  before do
    ada.affiliations.create!(organization: acme)
    grace.affiliations.create!(organization: acme)
  end

  def data
    json['data']
  end

  def error
    json['errors'].first
  end

  describe 'sessions' do
    let(:login) { 'mutation($session: SessionInput!) { create_session(session: $session) { token expires_at user { name } } }' }

    it 'logs in, and the token works for queries' do
      graphql(login, headers: {}, variables: { session: { email: 'ADA@example.com ', password: 'secret-password' } })
      token = data['create_session']['token']

      expect(data['create_session']['user']).to eq('name' => 'Ada')
      graphql('{ session(id: "current") { user { name } token } }', headers: { 'Authorization' => "Bearer #{token}" })
      expect(data['session']).to eq('user' => { 'name' => 'Ada' }, 'token' => nil)
    end

    it 'rejects a wrong password, writing nothing' do
      graphql(login, headers: {}, variables: { session: { email: ada.email, password: 'wrong' } })

      expect(data).to eq('create_session' => nil)
      expect(error['extensions']).to include('code' => 'unauthorized', 'status' => 401)
      expect(AuthDB::Session.count).to eq(0)
    end

    it 'logs out' do
      headers = user_headers(ada)
      graphql('mutation { delete_session(id: "current") { id } }', headers: headers)
      graphql('{ users { nodes { name } } }', headers: headers)

      expect(error['extensions']['code']).to eq('unauthorized')
    end
  end

  describe 'as an application' do
    it 'creates an organization, recording the application, and a user in it' do
      headers = app_headers
      graphql('mutation { create_organization(organization: { name: "Globex", slug: "globex" }) { id slug application { name } } }',
              headers: headers)
      globex = data['create_organization']
      expect(globex).to include('slug' => 'globex', 'application' => { 'name' => 'billing' })

      user = { name: 'Linus', email: 'linus@example.com', password: 'secret-password',
               affiliations: [{ organization_id: globex['id'], affiliation_attributes: { title: 'Lead', manager_user_id: ada.id } }] }
      graphql(<<~GRAPHQL, headers: headers, variables: { user: user })
        mutation($user: UserInput!) {
          create_user(user: $user) { name affiliations { organization { slug } affiliation_attributes { title manager_user { name } } } }
        }
      GRAPHQL

      expect(data['create_user']).to eq('name' => 'Linus', 'affiliations' => [{
                                          'organization' => { 'slug' => 'globex' },
                                          'affiliation_attributes' => { 'title' => 'Lead', 'manager_user' => { 'name' => 'Ada' } }
                                        }])
    end

    it 'imports users with upsert, matched by email' do
      headers = app_headers
      mutation = 'mutation($user: UserInput!) { upsert_user(user: $user) { id name } }'
      graphql(mutation, headers: headers, variables: { user: { email: 'ada@example.com', name: 'Ada Lovelace' } })

      expect(data['upsert_user']).to eq('id' => ada.id, 'name' => 'Ada Lovelace')
    end

    it 'deletes users softly, ending their sessions' do
      user_headers(ada)
      graphql("mutation { delete_user(id: #{ada.id}) { name } }", headers: app_headers)

      expect(data['delete_user']).to eq('name' => 'Ada')
      expect(ada.reload.deleted_at).to be_present
      expect(ada.sessions.active).to be_empty
    end
  end

  describe 'as a user' do
    it 'updates their own account, and a new password ends their other sessions' do
      other_session = user_headers(ada)
      headers = user_headers(ada)
      graphql("mutation { update_user(id: #{ada.id}, user: { name: \"Ada L\", password: \"new-password\" }) { name } }",
              headers: headers)
      expect(data['update_user']).to eq('name' => 'Ada L')

      graphql('{ users { nodes { name } } }', headers: other_session)
      expect(error['extensions']['code']).to eq('unauthorized')
      graphql('{ users { nodes { name } } }', headers: headers)
      expect(json['errors']).to be_nil
    end

    it "can't change someone else, create organizations, or change their affiliations" do
      headers = user_headers(ada)
      graphql("mutation { update_user(id: #{grace.id}, user: { name: \"G\" }) { name } }", headers: headers)
      expect(error['message']).to eq('You can only change your own account')

      graphql('mutation { create_organization(organization: { name: "Mine", slug: "mine" }) { id } }', headers: headers)
      expect(error['message']).to eq('Only applications can do this')

      graphql("mutation { update_user(id: #{ada.id}, user: { name: \"Ada L\", affiliations: [{ organization_id: #{acme.id}, " \
              '_destroy: true }] }) { name } }', headers: headers)
      expect(error['extensions']['details']).to eq([{ 'field' => 'affiliations', 'error' => 'forbidden',
                                                      'message' => 'Only applications can change affiliations' }])
      expect(ada.reload).to have_attributes(name: 'Ada', affiliations: [have_attributes(organization_id: acme.id)])
    end

    it 'gets validation errors with their paths' do
      graphql("mutation { update_user(id: #{ada.id}, user: { email: \"nope\", password: \"short\" }) { name } }",
              headers: user_headers(ada))

      expect(error['extensions']['code']).to eq('validation_error')
      expect(error['extensions']['details'].map { |detail| detail['field'] }).to contain_exactly('email', 'password')
    end
  end
end
