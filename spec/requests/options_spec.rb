# frozen_string_literal: true

RSpec.describe 'schema options' do
  let(:manufacturer) { Manufacturer.create!(tenant_id: tenant.id, name: 'Ford Motor Co', code: 'FMC') }

  before { FleetCarsController.touched.clear }

  describe 'belongs_to key:, render_key:, on_put_missing: :nullify and a lambda scope' do
    it 'assigns by the key field and renders it' do
      car = create_car
      json_request :patch, "/fleet_cars/#{car.id}", car: { manufacturer_code: 'FMC' } if manufacturer

      expect(car.reload.manufacturer).to eq(manufacturer)
      expect(json['car']).to include('manufacturer_code' => 'FMC', 'manufacturer' => { 'name' => 'Ford Motor Co' })
      expect(json['car']['created_at']).to eq(car.created_at.to_i)
    end

    it 'clears the reference when PUT leaves the key out' do
      car = create_car(manufacturer: manufacturer)
      json_request :put, "/fleet_cars/#{car.id}", car: { vin: car.vin }

      expect(car.reload.manufacturer).to be_nil
    end

    it 'accepts scope: :all' do
      foreign = Manufacturer.create!(tenant_id: other_tenant.id, name: 'Elsewhere')
      car = create_car
      json_request :patch, "/garage_cars/#{car.id}", car: { manufacturer_id: foreign.id }

      expect(car.reload.manufacturer).to eq(foreign)
    end
  end

  describe 'on_remove' do
    let(:car) { create_car }
    let!(:owner) { car.owners.create!(person_id: 1) }

    it ':error refuses to remove children, whether left out or sent with _destroy' do
      json_request :put, "/strict_cars/#{car.id}", car: { owners: [] }

      expect(last_response.status).to eq(400)
      expect(json['error']['details']).to eq([{ 'field' => 'owners', 'error' => 'remove_not_allowed', 'message' => "Owners can't be removed" }])

      json_request :patch, "/strict_cars/#{car.id}", car: { owners: [{ id: owner.id, _destroy: true }] }
      expect(last_response.status).to eq(400)
      expect(owner.reload.car_id).to eq(car.id)
    end

    it ':nullify detaches children' do
      json_request :put, "/garage_cars/#{car.id}", car: { vin: car.vin, owners: [] }

      expect(owner.reload.car_id).to be_nil
    end

    it ':delete deletes children without callbacks' do
      json_request :put, "/dealer_cars/#{car.id}", car: { owners: [] }

      expect(Owner.exists?(owner.id)).to be(false)
    end

    it 'passes the removed paths to a touch proc' do
      json_request :patch, "/fleet_cars/#{car.id}", car: { owners: [{ id: owner.id, _destroy: true }] }

      expect(last_response.status).to eq(200)
      expect(FleetCarsController.touched).to eq([[car.id, ['owners']]])
    end
  end

  describe 'has_many matched by id' do
    let(:car) { create_car }
    let!(:owner) { car.owners.create!(person_id: 1) }

    it 'is not_found for an id that is not a child' do
      other = create_car.owners.create!(person_id: 2)
      json_request :patch, "/garage_cars/#{car.id}", car: { owners: [{ id: other.id, person_id: 3 }] }

      expect(last_response.status).to eq(400)
      expect(json['error']['details']).to eq([{ 'field' => 'owners[0]', 'error' => 'not_found', 'message' => "Owner #{other.id} does not exist" }])
      expect(other.reload.person_id).to eq(2)
    end

    it 'is not_found for a _destroy with an unknown id' do
      json_request :patch, "/fleet_cars/#{car.id}", car: { owners: [{ id: 0, _destroy: true }] }

      expect(json['error']['details'].first).to include('field' => 'owners[0]', 'error' => 'not_found')
    end

    it 'patch: :replace treats a PATCH list as the whole collection' do
      json_request :patch, "/garage_cars/#{car.id}", car: { owners: [{ person_id: 9 }] }

      expect(car.reload.owners.map(&:person_id)).to eq([9])
    end

    it 'calls a touch proc with the changes when only children changed' do
      json_request :patch, "/fleet_cars/#{car.id}", car: { owners: [{ id: owner.id, person_id: 7 }] }

      expect(FleetCarsController.touched).to eq([[car.id, []]])
    end
  end

  describe 'search operators' do
    it 'supports starts_with and null' do
      bronco = create_car(model: 'Bronco')
      blank = create_car(model: nil)
      get_json '/fleet_cars', model: { starts_with: 'Bro' }
      expect(json['cars'].map { |c| c['id'] }).to eq([bronco.id])

      get_json '/fleet_cars', model: { null: true }
      expect(json['cars'].map { |c| c['id'] }).to eq([blank.id])
    end

    it 'pages with cursors over time and decimal sorts' do
      cars = 3.times.map { |i| create_car(price: "1#{i}.5") }
      header 'X-Tenant-Id', tenant.id.to_s
      get '/cars', sort: '-created_at'
      first = json['cars'].map { |c| c['id'] }
      get '/cars', sort: '-created_at', cursor: json['meta']['next_cursor']

      expect(first + json['cars'].map { |c| c['id'] }).to eq(cars.reverse.map(&:id))
    end
  end

  describe 'bulk status:' do
    it 'uses the proc' do
      json_request :post, '/fleet_cars/bulk_create', cars: [{ model: 'X' }]
      expect(last_response.status).to eq(422)

      json_request :post, '/fleet_cars/bulk_create', cars: [{ vin: 'A' }, { model: 'X' }]
      expect(last_response.status).to eq(200)
    end

    it 'requires the bulk key on bulk_update' do
      json_request :patch, '/cars/bulk_update', cars: [{ make: 'Ford' }]

      expect(json['errors'].first['error']['details']).to eq([{ 'field' => 'id', 'error' => 'required', 'message' => 'Id is required to update' }])
    end
  end

  describe 'upsert races' do
    it 'retries once as an update when a concurrent create wins' do
      existing = create_car(vin: 'V1', make: 'Ford')
      calls = 0
      allow_any_instance_of(CarsController).to receive(:find_resource_for_upsert).and_wrap_original do |original, input|
        calls += 1
        calls == 1 ? nil : original.call(input)
      end
      json_request :put, '/cars/upsert', car: { vin: 'V1', make: 'Jeep' }

      expect(last_response.status).to eq(200)
      expect(existing.reload.make).to eq('Jeep')
    end
  end
end
