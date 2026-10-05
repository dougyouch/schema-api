# frozen_string_literal: true

RSpec.describe 'nested resources' do
  describe 'has_many matched by key' do
    let(:car) { create_car }

    before do
      car.owners.create!(person_id: 1, since: '2020-01-01')
      car.owners.create!(person_id: 2, since: '2021-01-01')
    end

    it 'PUT makes the list the whole collection' do
      json_request :put, "/cars/#{car.id}", car: { make: 'Ford', owners: [{ person_id: 2, since: '2022-02-02' }, { person_id: 3 }] }

      expect(last_response.status).to eq(200)
      owners = car.reload.owners.order(:person_id)
      expect(owners.map(&:person_id)).to eq([2, 3])
      expect(owners.first.since.to_s).to eq('2022-02-02')
    end

    it 'PUT without the list empties it' do
      json_request :put, "/cars/#{car.id}", car: { make: 'Ford' }
      expect(car.reload.owners).to be_empty
    end

    it 'PATCH changes only the items sent, creates new ones, and removes _destroy items' do
      json_request :patch, "/cars/#{car.id}", car: { owners: [{ person_id: 1, since: '2023-03-03' }, { person_id: 2, _destroy: true }, { person_id: 4 }] }

      expect(last_response.status).to eq(200)
      expect(car.reload.owners.order(:person_id).map { |o| [o.person_id, o.since&.to_s] }).to eq([[1, '2023-03-03'], [4, nil]])
      expect(json['car']['owners'].map { |o| o['person_id'] }).to contain_exactly(1, 4)
    end

    it 'PATCH without the list leaves it alone' do
      json_request :patch, "/cars/#{car.id}", car: { make: 'Jeep' }
      expect(car.reload.owners.count).to eq(2)
    end

    it 'rejects the same key twice' do
      json_request :patch, "/cars/#{car.id}", car: { owners: [{ person_id: 5 }, { person_id: 5 }] }

      expect(last_response.status).to eq(400)
      expect(json['error']['details']).to eq([{ 'field' => 'owners[1]', 'error' => 'duplicate_key', 'message' => 'Owners has the same key more than once' }])
    end

    it 'touches the root when only a child changed' do
      before = car.reload.updated_at
      json_request :patch, "/cars/#{car.id}", car: { owners: [{ person_id: 1, since: '2025-05-05' }] }

      expect(car.reload.updated_at).to be > before
    end

    it 'does not touch anything when nothing changed' do
      before = car.reload.updated_at
      json_request :patch, "/cars/#{car.id}", car: { make: 'Ford', owners: [{ person_id: 1, since: '2020-01-01' }] }

      expect(last_response.status).to eq(200)
      expect(car.reload.updated_at).to eq(before)
    end
  end

  describe 'JSON columns' do
    it 'PUT replaces the column and PATCH merges into it' do
      car = create_car(options: { 'color' => 'red', 'sunroof' => true })
      json_request :patch, "/cars/#{car.id}", car: { options: { color: 'blue' } }
      expect(car.reload.options).to eq('color' => 'blue', 'sunroof' => true)

      json_request :put, "/cars/#{car.id}", car: { make: 'Ford', options: { color: 'green' } }
      expect(car.reload.options).to eq('color' => 'green')
    end
  end

  describe 'deep trees' do
    let(:acme) { tenant }
    let(:user) { AuthDB::User.create!(tenant_id: acme.id, name: 'Ada', email: 'ada@example.com') }

    before { UsersController.events.clear }

    def put_user(method: :patch, **body)
      json_request method, "/users/#{user.id}", user: { updated_at: user.reload.updated_at.iso8601(6) }.merge(body)
    end

    it 'creates affiliations with their attributes row and roles' do
      put_user(affiliations: [{ tenant_id: acme.id, affiliation_roles: %w[admin billing], affiliation_attributes: { department: 'Eng', title: 'Lead' } }])

      expect(last_response.status).to eq(200)
      affiliation = user.affiliations.first
      expect(affiliation.roles.map(&:name)).to contain_exactly('admin', 'billing')
      expect(affiliation.details).to have_attributes(department: 'Eng', title: 'Lead')
      expect(json['user']['affiliations'].first).to include('tenant_id' => acme.id, 'affiliation_roles' => contain_exactly('admin', 'billing'),
                                                            'affiliation_attributes' => { 'department' => 'Eng', 'title' => 'Lead' })
    end

    context 'with an existing affiliation' do
      let!(:affiliation) do
        user.affiliations.create!(tenant_id: acme.id).tap do |a|
          a.create_details!(department: 'Eng', title: 'Lead')
          a.roles.create!(name: 'admin')
        end
      end

      it 'updates the attributes row in place and bumps the user with its own method' do
        details_id = affiliation.details.id
        put_user(affiliations: [{ tenant_id: acme.id, affiliation_attributes: { department: 'Sales' } }])

        expect(last_response.status).to eq(200)
        expect(affiliation.reload.details).to have_attributes(id: details_id, department: 'Sales', title: 'Lead')
        expect(user.reload.version_number).to eq(1)
        expect(UsersController.events).to include([:around_save_end, { created: [], updated: ['affiliations[0].affiliation_attributes'], removed: [] }])
      end

      it 'syncs roles' do
        put_user(affiliations: [{ tenant_id: acme.id, affiliation_roles: %w[billing] }])
        expect(affiliation.reload.roles.map(&:name)).to eq(%w[billing])
      end

      it 'does not bump the user when nothing changed' do
        put_user(affiliations: [{ tenant_id: acme.id, affiliation_roles: %w[admin] }])

        expect(last_response.status).to eq(200)
        expect(user.reload.version_number).to eq(0)
      end

      it 'validates nested schemas against the merged result, with request paths' do
        put_user(affiliations: [{ tenant_id: acme.id, affiliation_attributes: { title: 'CTO' } }])
        expect(last_response.status).to eq(200)

        put_user(affiliations: [{ tenant_id: acme.id, affiliation_attributes: { department: nil } }])
        expect(last_response.status).to eq(422)
        expect(json['error']['details']).to eq([{ 'field' => 'affiliations[0].affiliation_attributes.department', 'error' => 'blank', 'message' => "Department can't be blank" }])
      end

      it 'removes the attributes row when it is sent as null' do
        put_user(affiliations: [{ tenant_id: acme.id, affiliation_attributes: nil }])
        expect(affiliation.reload.details).to be_nil
      end
    end
  end
end
