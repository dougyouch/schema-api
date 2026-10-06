# frozen_string_literal: true

RSpec.describe 'GraphQL mutations' do
  let(:manufacturer) { Manufacturer.create!(tenant_id: tenant.id, name: 'Ford Motor Co') }
  let(:car) { create_car(make: 'Ford', model: 'Bronco', year: 2020) }

  def data
    json['data']
  end

  def error
    json['errors'].first
  end

  it 'creates through the write pipeline, nested records and references included' do
    input = { vin: 'VIN1', make: 'Ford', model: 'Bronco', price: '45000.50', manufacturer_id: manufacturer.id,
              owners: [{ person_id: 7, since: '2021-03-04' }], options: { color: 'red' } }
    graphql(<<~GRAPHQL, { car: input })
      mutation($car: CarInput!) {
        create_car(car: $car) { id vin price manufacturer { name } owners { person_id since } options { color sunroof } }
      }
    GRAPHQL

    created = Car.find(data['create_car']['id'])
    expect(created.tenant).to eq(tenant)
    expect(data['create_car']).to include('vin' => 'VIN1', 'price' => '45000.5', 'manufacturer' => { 'name' => 'Ford Motor Co' },
                                          'owners' => [{ 'person_id' => 7, 'since' => '2021-03-04' }],
                                          'options' => { 'color' => 'red', 'sunroof' => nil })
  end

  it 'reports validation and parsing errors with their paths' do
    graphql('mutation { create_car(car: { vin: "VIN1", make: "" }) { id } }')

    expect(data).to eq('create_car' => nil)
    expect(error['extensions']).to include('code' => 'validation_error', 'status' => 422)
    expect(error['extensions']['details']).to eq([{ 'field' => 'make', 'error' => 'blank', 'message' => "Make can't be blank" }])

    graphql('mutation { create_car(car: { vin: "VIN1", make: "Ford", price: "lots" }) { id } }')
    expect(error['extensions']).to include('code' => 'invalid_data')
    expect(error['extensions']['details']).to include(include('field' => 'price'))
    expect(Car.where(vin: 'VIN1')).to be_empty
  end

  it 'updates only what is sent, clears what is sent as null, and removes items with _destroy' do
    car.owners.create!(person_id: 7)
    car.owners.create!(person_id: 8)
    graphql(<<~GRAPHQL, { id: car.id, car: { year: 2021, model: nil, owners: [{ person_id: 7, _destroy: true }] } })
      mutation($id: ID!, $car: CarInput!) { update_car(id: $id, car: $car) { make model year owners { person_id } } }
    GRAPHQL

    expect(data['update_car']).to eq('make' => 'Ford', 'model' => nil, 'year' => 2021, 'owners' => [{ 'person_id' => 8 }])
  end

  it 'keeps the REST rules: create-only fields, optimistic locks and scoped references' do
    graphql("mutation { update_car(id: #{car.id}, car: { vin: \"OTHER\" }) { vin } }")
    expect(error['extensions']['details'].first).to include('field' => 'vin', 'error' => 'create_only_attribute')

    graphql("mutation { update_car(id: #{car.id}, car: { make: \"Jeep\", updated_at: \"2000-01-01T00:00:00Z\" }) { make } }")
    expect(error['extensions']).to include('code' => 'stale_resource', 'status' => 409)

    elsewhere = Manufacturer.create!(tenant_id: other_tenant.id, name: 'Elsewhere')
    graphql("mutation { update_car(id: #{car.id}, car: { manufacturer_id: #{elsewhere.id} }) { make } }")
    expect(error['extensions']['details'].first).to include('field' => 'manufacturer_id', 'error' => 'not_found')
    expect(car.reload).to have_attributes(make: 'Ford', manufacturer_id: nil)
  end

  it 'upserts by the upsert key' do
    mutation = 'mutation($car: CarInput!) { upsert_car(car: $car) { id make model } }'
    graphql(mutation, { car: { vin: 'UP1', make: 'Ford', model: 'Bronco' } })
    id = data['upsert_car']['id']
    graphql(mutation, { car: { vin: 'UP1', make: 'Jeep' } })

    expect(data['upsert_car']).to eq('id' => id, 'make' => 'Jeep', 'model' => 'Bronco')
  end

  it 'deletes within the scope, returning the record as it was' do
    graphql("mutation { delete_car(id: #{car.id}) { vin make } }")
    expect(data['delete_car']).to eq('vin' => car.vin, 'make' => 'Ford')
    expect(Car.exists?(car.id)).to be(false)

    other = create_car(tenant: other_tenant)
    graphql("mutation { delete_car(id: #{other.id}) { vin } }")
    expect(error['extensions']['code']).to eq('not_found')
    expect(Car.exists?(other.id)).to be(true)
  end

  it 'runs mutations in order, each in its own transaction' do
    graphql(<<~GRAPHQL)
      mutation {
        first: create_car(car: { vin: "A1", make: "Ford" }) { vin }
        second: create_car(car: { vin: "A2", make: "" }) { vin }
        third: update_car(id: #{car.id}, car: { make: "Jeep" }) { make }
      }
    GRAPHQL

    expect(data).to eq('first' => { 'vin' => 'A1' }, 'second' => nil, 'third' => { 'make' => 'Jeep' })
    expect(Car.where(vin: %w[A1 A2]).pluck(:vin)).to eq(%w[A1])
  end

  describe 'callbacks and nested validation' do
    before { UsersController.events.clear }

    it 'runs validate_input, save and commit callbacks, and validates nested records' do
      input = { name: 'Ada', email: 'ada@example.com', password: 'secret',
                affiliations: [{ tenant_id: tenant.id, affiliation_roles: %w[admin], affiliation_attributes: { department: 'Eng' } }] }
      graphql(<<~GRAPHQL, { user: input })
        mutation($user: UserInput!) {
          create_user(user: $user) { name affiliations { tenant_id affiliation_roles affiliation_attributes { department } } }
        }
      GRAPHQL

      expect(data['create_user']['affiliations']).to eq([{ 'tenant_id' => tenant.id, 'affiliation_roles' => %w[admin],
                                                           'affiliation_attributes' => { 'department' => 'Eng' } }])
      expect(UsersController.events.map(&:first)).to include(:before_save, :commit)

      graphql('mutation { create_user(user: { name: "Bo", password: "x", affiliations: [{ tenant_id: 0, ' \
              'affiliation_attributes: { title: "Lead" } }] }) { name } }')
      expect(error['extensions']['details'].map { |detail| detail['field'] })
        .to contain_exactly('affiliations[0].tenant_id', 'affiliations[0].affiliation_attributes.department')
    end
  end

  it 'only has mutations for the actions a controller has, with no output-only input fields' do
    schema = GraphqlController.graphql_schema
    input = schema.types['CarInput'].arguments.keys

    expect(schema.mutation.fields.keys).to contain_exactly(
      'create_car', 'update_car', 'upsert_car', 'delete_car', 'create_user', 'update_user', 'delete_user'
    )
    expect(input).to include('vin', 'make', 'manufacturer_id', 'owners', 'updated_at')
    expect(input).not_to include('id', 'label', 'manufacturer', 'created_at')
    expect(schema.types['CarOwnerInput'].arguments.keys).to contain_exactly('person_id', 'since', '_destroy')
    expect(schema.types['UserAffiliationInput'].arguments.keys).not_to include('id')
    expect(schema.types['UserInput'].arguments.keys).to include('password')
  end
end
