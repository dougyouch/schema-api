# frozen_string_literal: true

RSpec.describe 'write pipeline' do
  let(:user) { AuthDB::User.create!(tenant_id: tenant.id, name: 'Ada', email: 'ada@example.com') }

  before { UsersController.events.clear }

  describe 'optimistic locking' do
    it 'returns 409 stale_resource when the lock value is out of date' do
      car = create_car
      stale = car.updated_at.iso8601(6)
      car.update!(make: 'Jeep')
      json_request :patch, "/cars/#{car.id}", car: { model: 'X', updated_at: stale }

      expect(last_response.status).to eq(409)
      expect(json['error']['code']).to eq('stale_resource')
      expect(car.reload.model).to eq('Bronco')
    end

    it 'saves when the lock value matches, and skips the check when it is not sent' do
      car = create_car
      json_request :patch, "/cars/#{car.id}", car: { model: 'X', updated_at: car.updated_at.iso8601(6) }
      expect(last_response.status).to eq(200)

      json_request :patch, "/cars/#{car.id}", car: { model: 'Y' }
      expect(last_response.status).to eq(200)
    end

    it 'requires the lock value with lock: :required' do
      json_request :patch, "/users/#{user.id}", user: { name: 'Grace' }

      expect(last_response.status).to eq(400)
      expect(json['error']['details']).to eq([{ 'field' => 'updated_at', 'error' => 'required', 'message' => 'Updated at is required to update' }])
    end
  end

  describe 'callbacks and controller validations' do
    it 'runs validate_input with the context and reports its errors with schema errors' do
      json_request :patch, "/users/#{user.id}", user: { name: '', updated_at: user.updated_at.iso8601(6), affiliations: [{ tenant_id: 0 }] }

      expect(last_response.status).to eq(422)
      expect(json['error']['details']).to contain_exactly(
        { 'field' => 'name', 'error' => 'blank', 'message' => "Name can't be blank" },
        { 'field' => 'affiliations[0].tenant_id', 'error' => 'not_allowed', 'message' => 'Tenant is not one you belong to' }
      )
    end

    it 'runs before, around and after-commit callbacks in order' do
      json_request :post, '/users', user: { name: 'Grace', password: 'secret' }

      expect(last_response.status).to eq(201)
      id = json['user']['id']
      expect(UsersController.events).to eq([
                                             %i[before_save create],
                                             %i[around_save_start create],
                                             [:around_save_end, { created: [''], updated: [], removed: [] }],
                                             [:commit, id]
                                           ])
    end

    it 'uses the validation context, so on: :create validations only run on create' do
      json_request :post, '/users', user: { name: 'Grace' }
      expect(json['error']['details']).to eq([{ 'field' => 'password', 'error' => 'blank', 'message' => "Password can't be blank" }])

      json_request :patch, "/users/#{user.id}", user: { name: 'Grace', updated_at: user.updated_at.iso8601(6) }
      expect(last_response.status).to eq(200)
    end

    it 'never renders write-only fields' do
      json_request :post, '/users', user: { name: 'Grace', password: 'secret' }
      expect(json['user']).not_to have_key('password')
    end
  end
end
