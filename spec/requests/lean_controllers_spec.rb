# frozen_string_literal: true

RSpec.describe 'lean controller helpers' do
  def lean(method, path, user_id: 5, **body)
    header 'X-User-Id', user_id.to_s
    json_request method, path, body.empty? ? nil : body
  end

  describe 'include SchemaApi in a base controller' do
    it 'adds actions only to controllers that declare a schema' do
      expect(SchemaApplicationController.action_methods).to be_empty
      expect(LeanCarsController.action_methods).to include('index', 'create')
    end

    it 'renders errors from any controller in the standard format, and parses with SchemaApi.parse!' do
      get '/ping', deny: 1
      expect(last_response.status).to eq(403)
      expect(json['error']).to include('code' => 'forbidden', 'message' => 'Not today')

      get '/ping', count: 'x'
      expect(last_response.status).to eq(400)
      expect(json['error']['details'].map { |d| [d['field'], d['error']] }).to contain_exactly(%w[count invalid], %w[count blank])

      get '/ping'
      expect(last_response.status).to eq(422)

      get '/ping', count: 3
      expect(json).to eq('pong' => 3)
    end
  end

  describe 'write-only fields' do
    it 'are written when sent, kept when PUT leaves them out, and never rendered' do
      lean :post, '/lean_cars', car: { vin: 'V1', make: 'Ford', pin: '1234' }
      car = Car.find(json['car']['id'])
      expect(car.pin).to eq('1234')
      expect(json['car']).not_to have_key('pin')

      lean :put, "/lean_cars/#{car.id}", car: { vin: 'V1', make: 'Jeep' }
      expect(car.reload).to have_attributes(make: 'Jeep', pin: '1234')

      lean :put, "/lean_cars/#{car.id}", car: { vin: 'V1', make: 'Jeep', pin: nil }
      expect(car.reload.pin).to be_nil
    end
  end

  describe 'set: fields' do
    it 'are filled by the server, ignoring the client, and only when the record changes' do
      lean :post, '/lean_cars', car: { vin: 'V1', make: 'Ford', created_by_id: 99 }, user_id: 5
      car = Car.find(json['car']['id'])
      expect(json['car']).to include('created_by_id' => 5, 'updated_by_id' => 5)

      lean :patch, "/lean_cars/#{car.id}", car: { make: 'Ford' }, user_id: 7
      expect(car.reload.updated_by_id).to eq(5)

      lean :patch, "/lean_cars/#{car.id}", car: { make: 'Jeep' }, user_id: 7
      expect(car.reload).to have_attributes(created_by_id: 5, updated_by_id: 7)
    end

    it "can't also be input" do
      kls = Class.new(ActionController::API) do
        include SchemaApi

        def self.name
          'BadSetCarsController'
        end

        schema(Car) { model_attribute :created_by_id, input: true, set: :whoever }
      end

      expect { kls.schema_api_definition.finalize! }.to raise_error(SchemaApi::DefinitionError, /set: fields are set by the server/)
    ensure
      SchemaApi.controllers.delete(kls)
    end
  end

  describe 'model_attributes, timestamps and includes:' do
    it 'declares the attributes and loads what computed fields need' do
      create_car.owners.create!(person_id: 1)
      lean :get, '/lean_cars'

      expect(json['cars'].first.keys).to eq(%w[id vin make created_by_id updated_by_id owner_count created_at updated_at])
      expect(json['cars'].first['owner_count']).to eq(1)
      expect(LeanCarsController.schema_api_definition.includes).to eq(owners: {})
      expect(LeanCarsController.schema_api_definition.schema_class.api_field(:updated_at).lock).to be(true)
    end

    it 'normalizes includes: forms' do
      expect(SchemaApi::IncludesBuilder.normalize([:a, { b: :c }, { b: [:d] }])).to eq(a: {}, b: { c: {}, d: {} })
    end
  end

  describe 'soft_delete' do
    it 'sets the timestamp on destroy and hides the row afterwards' do
      car = create_car
      lean :delete, "/lean_cars/#{car.id}"

      expect(last_response.status).to eq(204)
      expect(car.reload.deleted_at).to be_present
      lean :get, "/lean_cars/#{car.id}"
      expect(last_response.status).to eq(404)
      lean :get, '/lean_cars'
      expect(json['cars']).to eq([])
    end
  end

  describe 'parent' do
    it "scopes the resource to the parent's association and builds through it" do
      car = create_car
      car.owners.create!(person_id: 1)
      create_car.owners.create!(person_id: 2)

      lean :get, "/lean_cars/#{car.id}/owners"
      expect(json['owners'].map { |o| o['person_id'] }).to eq([1])

      lean :post, "/lean_cars/#{car.id}/owners", owner: { person_id: 3 }
      expect(last_response.status).to eq(201)
      expect(car.owners.reload.map(&:person_id)).to eq([1, 3])
    end

    it "is a 404 when the parent isn't in scope" do
      lean :get, "/lean_cars/#{create_car(tenant: other_tenant).id}/owners"

      expect(last_response.status).to eq(404)
      expect(json['error']['message']).to eq('Owner not found')
    end

    it 'needs association: when it cannot be inferred' do
      expect { lean :get, "/tenants/#{tenant.id}/owners" }.to raise_error(SchemaApi::DefinitionError, /pass association: to parent/)
    end
  end
end
