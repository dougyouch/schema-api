# frozen_string_literal: true

RSpec.describe 'upsert and bulk actions' do
  describe 'PUT /cars/upsert' do
    it 'creates when the key is new, and updates when it exists' do
      json_request :put, '/cars/upsert', car: { vin: 'V1', make: 'Ford', year: 2020 }
      expect(last_response.status).to eq(201)
      id = json['car']['id']

      json_request :put, '/cars/upsert', car: { vin: 'V1', make: 'Jeep' }
      expect(last_response.status).to eq(200)
      expect(Car.find(id)).to have_attributes(make: 'Jeep', year: nil)
    end

    it 'merges on PATCH' do
      car = create_car(vin: 'V1', year: 2020)
      json_request :patch, '/cars/upsert', car: { vin: 'V1', make: 'Jeep' }

      expect(car.reload).to have_attributes(make: 'Jeep', year: 2020)
    end

    it 'looks only within the scope' do
      create_car(tenant: other_tenant, vin: 'V1')
      json_request :put, '/cars/upsert', car: { vin: 'V1', make: 'Ford' }

      expect(last_response.status).to eq(201)
    end

    it 'requires the key' do
      json_request :put, '/cars/upsert', car: { make: 'Ford' }

      expect(last_response.status).to eq(400)
      expect(json['error']['details']).to eq([{ 'field' => 'vin', 'error' => 'missing_upsert_key', 'message' => 'Vin is required to upsert' }])
    end
  end

  describe 'POST /cars/bulk_create' do
    it 'saves what it can and reports the rest by index' do
      json_request :post, '/cars/bulk_create', cars: [{ vin: 'A', make: 'Ford' }, { vin: 'B', make: '' }, 'junk']

      expect(last_response.status).to eq(200)
      expect(json['cars'][0]).to include('vin' => 'A')
      expect(json['cars'][1..]).to eq([nil, nil])
      expect(json['errors'].map { |e| [e['index'], e['error']['code']] }).to eq([[1, 'validation_error'], [2, 'invalid_data']])
      expect(json['meta']).to eq('created' => 1, 'updated' => 0, 'failed' => 2)
      expect(Car.pluck(:vin)).to eq(['A'])
    end

    it 'rejects more items than bulk max' do
      json_request :post, '/cars/bulk_create', cars: Array.new(4) { |i| { vin: i.to_s, make: 'Ford' } }

      expect(last_response.status).to eq(400)
      expect(json['error']['message']).to eq('At most 3 items are allowed per request')
      expect(Car.count).to eq(0)
    end
  end

  describe 'PATCH /cars/bulk_update' do
    it 'matches by id, reporting missing and duplicate ids per item' do
      ford = create_car(make: 'Ford')
      foreign = create_car(tenant: other_tenant)
      json_request :patch, '/cars/bulk_update', cars: [{ id: ford.id, model: 'Maverick' }, { id: foreign.id, model: 'X' }, { id: ford.id, model: 'Y' }]

      expect(ford.reload.model).to eq('Maverick')
      expect(json['errors'].map { |e| [e['index'], e['error']['code']] }).to eq([[1, 'not_found'], [2, 'invalid_data']])
      expect(json['meta']).to eq('created' => 0, 'updated' => 1, 'failed' => 2)
    end
  end

  describe 'PUT /cars/bulk_upsert' do
    it 'creates and updates by upsert key in one request' do
      existing = create_car(vin: 'OLD', make: 'Ford')
      json_request :put, '/cars/bulk_upsert', cars: [{ vin: 'OLD', make: 'Jeep' }, { vin: 'NEW', make: 'Ram' }]

      expect(json['meta']).to eq('created' => 1, 'updated' => 1, 'failed' => 0)
      expect(existing.reload.make).to eq('Jeep')
      expect(Car.find_by(vin: 'NEW').make).to eq('Ram')
    end
  end

  describe 'bulk atomic: true' do
    it 'rolls everything back when any item fails, and returns 422' do
      json_request :post, '/atomic_cars/bulk_create', car: nil, atomic_cars: nil, cars: [{ vin: 'A', make: 'Ford', year: 2020 }, { vin: 'B', make: 'Ford' }]

      expect(last_response.status).to eq(422)
      expect(json['cars']).to eq([nil, nil])
      expect(json['errors'].map { |e| e['index'] }).to eq([1])
      expect(json['meta']).to eq('created' => 0, 'updated' => 0, 'failed' => 1)
      expect(Car.count).to eq(0)
    end

    it 'saves everything when all items pass' do
      json_request :post, '/atomic_cars/bulk_create', cars: [{ vin: 'A', make: 'Ford', year: 2020 }, { vin: 'B', make: 'Ford', year: 2021 }]

      expect(last_response.status).to eq(200)
      expect(Car.count).to eq(2)
    end
  end
end
