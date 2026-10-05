# frozen_string_literal: true

RSpec.describe 'CRUD actions' do
  let(:manufacturer) { Manufacturer.create!(tenant_id: tenant.id, name: 'Ford Motor Co', code: 'FMC') }

  describe 'GET /cars/:id' do
    it 'renders the schema, with every field and nils included' do
      car = create_car(manufacturer: manufacturer, price: '12.50', options: { 'color' => 'red' })
      car.owners.create!(person_id: 7, since: '2024-01-31')
      get_json "/cars/#{car.id}"

      expect(last_response.status).to eq(200)
      expect(json['car']).to include(
        'id' => car.id, 'make' => 'Ford', 'price' => '12.5', 'status' => 'active', 'label' => '2020 Ford Bronco',
        'manufacturer' => { 'id' => manufacturer.id, 'name' => 'Ford Motor Co' },
        'owners' => [{ 'id' => car.owners.first.id, 'person_id' => 7, 'since' => '2024-01-31' }],
        'options' => { 'color' => 'red', 'sunroof' => nil }
      )
      expect(json['car']).not_to have_key('manufacturer_id')
      expect(json['car']['created_at']).to eq(car.created_at.iso8601)
      expect(json['car']['updated_at']).to eq(car.updated_at.iso8601(6))
    end

    it "is a 404 for another tenant's car" do
      car = create_car(tenant: other_tenant)
      get_json "/cars/#{car.id}"

      expect(last_response.status).to eq(404)
      expect(json).to eq('error' => { 'code' => 'not_found', 'message' => 'Car not found', 'details' => [] })
    end
  end

  describe 'POST /cars' do
    it 'creates the car and its nested records, and returns 201' do
      json_request :post, '/cars', car: {
        vin: 'V1', make: 'Ford', model: 'Bronco', year: '2021', price: '30000.10', manufacturer_id: manufacturer.id,
        owners: [{ person_id: 1, since: '2024-02-01' }], options: { color: 'blue', sunroof: 'yes' }
      }

      expect(last_response.status).to eq(201)
      car = Car.find(json['car']['id'])
      expect(car).to have_attributes(tenant_id: tenant.id, vin: 'V1', year: 2021, price: BigDecimal('30000.10'), manufacturer: manufacturer)
      expect(car.owners.map(&:person_id)).to eq([1])
      expect(car.options).to eq('color' => 'blue', 'sunroof' => true)
      expect(json['car']['owners'].first['person_id']).to eq(1)
    end

    it 'ignores read-only fields' do
      json_request :post, '/cars', car: { vin: 'V1', make: 'Ford', id: 999, created_at: '2001-01-01T00:00:00Z', label: 'x' }

      expect(last_response.status).to eq(201)
      expect(json['car']['id']).not_to eq(999)
      expect(Car.last.created_at.year).not_to eq(2001)
    end

    it 'reports bad types and unknown fields as 400 invalid_data, with validation errors too' do
      json_request :post, '/cars', car: { vin: 'V1', year: 'abc', color: 'red', owners: [{ person_id: 'x' }] }

      expect(last_response.status).to eq(400)
      expect(json['error']['code']).to eq('invalid_data')
      expect(json['error']['details']).to contain_exactly(
        { 'field' => 'year', 'error' => 'invalid', 'message' => 'Year is invalid' },
        { 'field' => 'color', 'error' => 'unknown_attribute', 'message' => 'Color is an unknown attribute' },
        { 'field' => 'owners[0].person_id', 'error' => 'invalid', 'message' => 'Person is invalid' }
      )
      expect(Car.count).to eq(0)
    end

    it 'reports schema validations as 422' do
      json_request :post, '/cars', car: { vin: 'V1', make: '' }

      expect(last_response.status).to eq(422)
      expect(json['error']).to eq('code' => 'validation_error', 'message' => 'Car is invalid',
                                  'details' => [{ 'field' => 'make', 'error' => 'blank', 'message' => "Make can't be blank" }])
    end

    it 'reports model validations as 422 with API field paths' do
      json_request :post, '/cars', car: { vin: 'V1', make: 'Ford', year: 1800, owners: [{ since: '2024-01-01' }] }

      expect(last_response.status).to eq(422)
      expect(json['error']['details']).to eq([{ 'field' => 'year', 'error' => 'greater_than', 'message' => 'Year must be greater than 1885' }])
    end

    it 'reports nested model validations at their path' do
      json_request :post, '/cars', car: { vin: 'V1', make: 'Ford', owners: [{ person_id: 1 }, { since: '2024-01-01' }] }

      expect(last_response.status).to eq(422)
      expect(json['error']['details']).to eq([{ 'field' => 'owners[1].person_id', 'error' => 'blank', 'message' => "Person can't be blank" }])
      expect(Car.count).to eq(0)
    end

    it 'is a 409 conflict on a unique index' do
      create_car(vin: 'V1')
      json_request :post, '/cars', car: { vin: 'V1', make: 'Ford' }

      expect(last_response.status).to eq(409)
      expect(json['error']['code']).to eq('conflict')
    end

    it 'rejects malformed bodies' do
      json_request :post, '/cars', nil
      header 'Content-Type', 'application/json'
      post '/cars', '{nope'
      expect(json['error']).to include('code' => 'malformed_request', 'message' => 'Request body is not valid JSON')

      json_request :post, '/cars', make: 'Ford'
      expect(last_response.status).to eq(400)
      expect(json['error']['message']).to eq('Expected a JSON object with a "car" key')

      json_request :post, '/cars', car: [1]
      expect(json['error']['message']).to eq('Expected an object under "car"')
    end
  end

  describe 'PUT /cars/:id' do
    it 'replaces input fields, setting the ones not sent to nil' do
      car = create_car(year: 2020, price: 10)
      json_request :put, "/cars/#{car.id}", car: { make: 'Jeep' }

      expect(last_response.status).to eq(200)
      expect(car.reload).to have_attributes(make: 'Jeep', model: nil, year: nil, price: nil)
    end

    it 'accepts a create-only field with its stored value, and rejects a change' do
      car = create_car(vin: 'V1')
      json_request :put, "/cars/#{car.id}", car: { vin: 'V1', make: 'Jeep' }
      expect(last_response.status).to eq(200)

      json_request :put, "/cars/#{car.id}", car: { vin: 'V2', make: 'Jeep' }
      expect(last_response.status).to eq(400)
      expect(json['error']['details']).to eq([{ 'field' => 'vin', 'error' => 'create_only_attribute', 'message' => 'Vin can only be set on create' }])
    end

    it 'rejects an id that does not match the URL' do
      car = create_car
      json_request :put, "/cars/#{car.id}", car: { id: car.id + 1, make: 'Jeep' }

      expect(last_response.status).to eq(400)
      expect(json['error']['details'].first['error']).to eq('id_mismatch')
    end

    it 'accepts its own GET response back' do
      car = create_car(manufacturer: manufacturer)
      car.owners.create!(person_id: 3)
      get_json "/cars/#{car.id}"
      body = json
      json_request :put, "/cars/#{car.id}", body

      expect(last_response.status).to eq(200)
      expect(car.reload.manufacturer).to eq(manufacturer)
      expect(car.owners.count).to eq(1)
    end
  end

  describe 'PATCH /cars/:id' do
    it 'changes only the fields sent, including nulls' do
      car = create_car(year: 2020, model: 'Bronco')
      json_request :patch, "/cars/#{car.id}", car: { make: 'Jeep', year: nil }

      expect(last_response.status).to eq(200)
      expect(car.reload).to have_attributes(make: 'Jeep', year: nil, model: 'Bronco')
    end

    it 'validates the result, so required fields not sent still pass' do
      car = create_car
      json_request :patch, "/cars/#{car.id}", car: { model: 'Maverick' }
      expect(last_response.status).to eq(200)

      json_request :patch, "/cars/#{car.id}", car: { make: nil }
      expect(last_response.status).to eq(422)
    end
  end

  describe 'DELETE /cars/:id' do
    it 'destroys the car and returns 204' do
      car = create_car
      json_request :delete, "/cars/#{car.id}"

      expect(last_response.status).to eq(204)
      expect(Car.exists?(car.id)).to be(false)
    end
  end

  describe 'schema(actions:)' do
    it 'only defines the listed actions' do
      expect(NotesController.action_methods).to contain_exactly('index', 'show')
      expect { json_request :post, '/notes', note: { make: 'Ford' } }.to raise_error(AbstractController::ActionNotFound)
    end
  end
end
