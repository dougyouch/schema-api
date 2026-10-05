# frozen_string_literal: true

RSpec.describe 'belongs_to references' do
  let(:manufacturer) { Manufacturer.create!(tenant_id: tenant.id, name: 'Ford Motor Co') }
  let(:other_manufacturer) { Manufacturer.create!(tenant_id: tenant.id, name: 'Jeep') }

  it 'assigns by key and renders the object' do
    car = create_car
    json_request :patch, "/cars/#{car.id}", car: { manufacturer_id: manufacturer.id }

    expect(car.reload.manufacturer).to eq(manufacturer)
    expect(json['car']['manufacturer']).to eq('id' => manufacturer.id, 'name' => 'Ford Motor Co')
  end

  it 'ignores the nested object, even when it disagrees with the key' do
    car = create_car(manufacturer: manufacturer)
    json_request :patch, "/cars/#{car.id}", car: {
      manufacturer_id: other_manufacturer.id, manufacturer: { id: manufacturer.id, name: 'Renamed' }
    }

    expect(car.reload.manufacturer).to eq(other_manufacturer)
    expect(manufacturer.reload.name).to eq('Ford Motor Co')
  end

  it 'does not change the reference from the nested object alone' do
    car = create_car(manufacturer: manufacturer)
    json_request :patch, "/cars/#{car.id}", car: { manufacturer: { id: other_manufacturer.id } }

    expect(last_response.status).to eq(200)
    expect(car.reload.manufacturer).to eq(manufacturer)
  end

  it 'keeps the reference when PUT does not send the key, and clears it on null' do
    car = create_car(manufacturer: manufacturer)
    json_request :put, "/cars/#{car.id}", car: { make: 'Ford' }
    expect(car.reload.manufacturer).to eq(manufacturer)

    json_request :put, "/cars/#{car.id}", car: { make: 'Ford', manufacturer_id: nil }
    expect(car.reload.manufacturer).to be_nil
  end

  it 'ignores the key of an output-only belongs_to' do
    car = create_car(manufacturer: manufacturer)
    json_request :patch, "/lean_cars/#{car.id}", car: { manufacturer_id: other_manufacturer.id, make: 'Jeep' }

    expect(last_response.status).to eq(200)
    expect(car.reload).to have_attributes(make: 'Jeep', manufacturer: manufacturer)
  end

  it 'is a 422 when the key is outside the scope' do
    foreign = Manufacturer.create!(tenant_id: other_tenant.id, name: 'Elsewhere')
    car = create_car
    json_request :patch, "/cars/#{car.id}", car: { manufacturer_id: foreign.id }

    expect(last_response.status).to eq(422)
    expect(json['error']['details']).to eq([{ 'field' => 'manufacturer_id', 'error' => 'not_found', 'message' => "Manufacturer #{foreign.id} does not exist" }])
  end
end
