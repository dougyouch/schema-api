# frozen_string_literal: true

RSpec.describe 'belongs_to keys as match and upsert keys' do
  let(:ada) { Person.create!(name: 'Ada') }
  let(:grace) { Person.create!(name: 'Grace') }
  let(:car) { create_car }

  it 'matches has_many items by a belongs_to key' do
    car.owners.create!(person: ada, since: '2020-01-01')
    json_request :patch, "/people_cars/#{car.id}", car: { owners: [{ person_id: ada.id, since: '2024-04-04' }, { person_id: grace.id }] }

    expect(last_response.status).to eq(200)
    expect(car.reload.owners.order(:id).map { |o| [o.person_id, o.since&.to_s] }).to eq([[ada.id, '2024-04-04'], [grace.id, nil]])
    expect(json['car']['owners'].map { |o| o['person'] }).to eq([{ 'name' => 'Ada' }, { 'name' => 'Grace' }])
  end

  it 'upserts by belongs_to keys and filters by them' do
    json_request :put, '/owner_records/upsert', owner: { car_id: car.id, person_id: ada.id, since: '2020-01-01' }
    expect(last_response.status).to eq(201)

    json_request :put, '/owner_records/upsert', owner: { car_id: car.id, person_id: ada.id, since: '2021-01-01' }
    expect(last_response.status).to eq(200)
    expect(Owner.where(car: car, person: ada).pluck(:since).map(&:to_s)).to eq(['2021-01-01'])

    get_json '/owner_records', person_id: ada.id
    expect(json['owners'].map { |o| o['car'] }).to eq([{ 'vin' => car.vin }])
  end

  it 'requires upsert and bulk keys stored in a column' do
    kls = Class.new(ActionController::API) do
      include SchemaApi

      def self.name
        'BadKeyCarsController'
      end

      schema(Car) do
        model_attribute :id
        attribute :label, :string, value: :make.to_proc
      end
      upsert_key :label
    end

    expect { kls.schema_api_definition.finalize! }.to raise_error(SchemaApi::DefinitionError, /key label isn't a schema field stored in a model column/)
  ensure
    SchemaApi.controllers.delete(kls)
  end
end
