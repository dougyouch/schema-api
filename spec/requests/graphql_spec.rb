# frozen_string_literal: true

RSpec.describe 'GraphQL queries' do
  let(:manufacturer) { Manufacturer.create!(tenant_id: tenant.id, name: 'Ford Motor Co') }
  let!(:bronco) do
    create_car(make: 'Ford', model: 'Bronco', year: 2020, price: '45000.5', manufacturer: manufacturer,
               options: { color: 'red', sunroof: true })
  end
  let!(:maverick) { create_car(make: 'Ford', model: 'Maverick', year: 2023, status: :sold) }
  let!(:wrangler) { create_car(make: 'Jeep', model: 'Wrangler', year: 2018) }

  before do
    create_car(tenant: other_tenant, make: 'Ford')
    bronco.owners.create!(person_id: 7, since: Date.new(2021, 3, 4))
  end

  def data
    json['data']
  end

  def errors
    json['errors']
  end

  def ids(field = 'cars')
    data[field]['nodes'].map { |node| node['id'] }
  end

  it 'renders the same values as the REST endpoint, nested fields included' do
    graphql(<<~GRAPHQL)
      { cars(sort: "year") { nodes {
          id vin make label price status created_at updated_at
          manufacturer { id name }
          owners { id person_id since }
          options { color sunroof }
      } } }
    GRAPHQL
    node = data['cars']['nodes'].find { |car| car['id'] == bronco.id }

    get_json "/cars/#{bronco.id}"
    expect(node).to eq(json['car'].slice(*node.keys))
    expect(node).to include('price' => '45000.5', 'label' => '2020 Ford Bronco',
                            'owners' => [{ 'id' => bronco.owners.first.id, 'person_id' => 7, 'since' => '2021-03-04' }],
                            'options' => { 'color' => 'red', 'sunroof' => true })
  end

  it 'lists through the controller: resource_scope, default sort, limit and meta' do
    graphql('{ cars { nodes { id } meta { limit next_cursor total_count } } }')

    expect(last_response.status).to eq(200)
    expect(ids).to eq([bronco.id, maverick.id])
    expect(data['cars']['meta']).to match('limit' => 2, 'next_cursor' => a_kind_of(String), 'total_count' => nil)
  end

  it 'filters with every kind of declared filter, typed by the schema' do
    graphql('{ cars(filter: { make: { eq: "Ford" } }, limit: 5) { nodes { id } } }')
    expect(ids).to eq([bronco.id, maverick.id])

    graphql('{ cars(filter: { year: { gte: 2019, lte: 2021 } }) { nodes { id } } }')
    expect(ids).to eq([bronco.id])

    graphql('{ cars(filter: { status: { in: ["sold"] } }) { nodes { id } } }')
    expect(ids).to eq([maverick.id])

    graphql('{ cars(filter: { owners_person_id: { eq: 7 }, model: { contains: "ron" } }) { nodes { id } } }')
    expect(ids).to eq([bronco.id])

    graphql('{ cars(filter: { q: { eq: "rang" } }) { nodes { id } } }')
    expect(ids).to eq([wrangler.id])
  end

  it 'sorts, pages with cursors and offsets, and counts when asked' do
    graphql('query($cursor: String) { cars(sort: "-year", cursor: $cursor) { nodes { id } meta { next_cursor } } }')
    first_page = ids
    graphql('query($cursor: String) { cars(sort: "-year", cursor: $cursor) { nodes { id } meta { next_cursor } } }',
            { cursor: data['cars']['meta']['next_cursor'] })

    expect(first_page + ids).to eq([maverick.id, bronco.id, wrangler.id])

    graphql('{ cars(page: 2, count: true) { nodes { id } meta { page next_page total_count total_pages } } }')
    expect(ids).to eq([wrangler.id])
    expect(data['cars']['meta']).to eq('page' => 2, 'next_page' => nil, 'total_count' => 3, 'total_pages' => 2)
  end

  it 'reports bad search arguments with the REST error code and details, leaving other fields' do
    graphql('{ cars(limit: 50, sort: "vin") { nodes { id } } notes { nodes { id } } }')

    expect(data['cars']).to be_nil
    expect(data['notes']['nodes']).not_to be_empty
    expect(errors.first).to include('path' => ['cars'])
    expect(errors.first['extensions']).to include('code' => 'invalid_data', 'status' => 400)
    expect(errors.first['extensions']['details'].map { |detail| detail['field'] }).to contain_exactly('limit', 'sort')
  end

  it 'finds one record within the scope' do
    graphql("{ car(id: #{bronco.id}) { id make } }")
    expect(data['car']).to eq('id' => bronco.id, 'make' => 'Ford')

    other = Car.find_by!(tenant: other_tenant)
    graphql('query($id: ID!) { car(id: $id) { id } }', { id: other.id.to_s })
    expect(data['car']).to be_nil
    expect(errors.first).to include('message' => 'Car not found')
    expect(errors.first['extensions']).to include('code' => 'not_found', 'status' => 404)
  end

  it 'runs the controller callbacks for the action each field stands for' do
    graphql('{ guarded_notes { nodes { id } } }')
    expect(errors.first['message']).to eq('GuardedNotesController#index stopped the request (status 401)')
    expect(errors.first['extensions']['code']).to eq('forbidden')

    header 'X-Let-In', '1'
    graphql("{ guarded_notes { nodes { id } } guarded_note(id: #{bronco.id}) { id } }")
    expect(ids('guarded_notes')).to eq([bronco.id, maverick.id, wrangler.id])
    expect(data['guarded_note']).to be_nil
    expect(errors.first).to include('message' => 'Notes are only listed', 'path' => ['guarded_note'])
  end

  it 'only exposes rendered fields, and validates the query against them' do
    graphql('{ guarded_notes { nodes { id pin } } }')

    expect(json).not_to have_key('data')
    expect(errors.first['message']).to eq("Field 'pin' doesn't exist on type 'GuardedNote'")
  end

  it 'leaves out fields for actions the controller does not have' do
    fields = GraphqlController.graphql_schema.query.fields.keys

    expect(fields).to contain_exactly('cars', 'car', 'notes', 'note', 'guarded_notes', 'guarded_note')
    expect(GraphqlController.graphql_schema.to_definition).to include('owners_person_id: CarOwnersPersonIdFilter')
  end

  it 'accepts variables as a JSON string and picks the named operation' do
    json_request(:post, '/graphql', {
                   query: 'query A { notes { nodes { id } } } query B($id: ID!) { car(id: $id) { make } }',
                   variables: JSON.generate(id: wrangler.id), operationName: 'B'
                 })

    expect(data).to eq('car' => { 'make' => 'Jeep' })
  end

  it 'rejects a body that is not a GraphQL request' do
    json_request(:post, '/graphql', { variables: {} })

    expect(last_response.status).to eq(400)
    expect(json['error']).to include('code' => 'malformed_request', 'message' => 'query is required')
  end
end
