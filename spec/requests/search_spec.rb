# frozen_string_literal: true

RSpec.describe 'index: search, sort and pagination' do
  let!(:bronco) { create_car(make: 'Ford', model: 'Bronco', year: 2020) }
  let!(:maverick) { create_car(make: 'Ford', model: 'Maverick', year: 2023, status: :sold) }
  let!(:wrangler) { create_car(make: 'Jeep', model: 'Wrangler', year: 2018) }

  before { create_car(tenant: other_tenant, make: 'Ford') }

  def ids
    json['cars'].map { |car| car['id'] }
  end

  it 'lists only the scope, sorted by id, with a limit' do
    get_json '/cars'

    expect(last_response.status).to eq(200)
    expect(ids).to eq([bronco.id, maverick.id])
    expect(json['meta']).to include('limit' => 2, 'next_cursor' => a_kind_of(String))
  end

  it 'filters with eq, contains, ranges, in, nested fields and custom blocks' do
    get_json '/cars', make: 'Ford', limit: 5
    expect(ids).to eq([bronco.id, maverick.id])

    get_json '/cars', model: 'ave'
    expect(ids).to eq([maverick.id])

    get_json '/cars', year: { gte: 2019, lte: 2021 }
    expect(ids).to eq([bronco.id])

    get_json '/cars', status: 'sold,active', limit: 5
    expect(ids).to eq([bronco.id, maverick.id, wrangler.id])

    wrangler.owners.create!(person_id: 9)
    get_json '/cars', 'owners.person_id' => 9
    expect(ids).to eq([wrangler.id])

    get_json '/cars', q: 'rang'
    expect(ids).to eq([wrangler.id])
  end

  it 'sorts by declared fields, with descending and multiple fields' do
    get_json '/cars', sort: '-year', limit: 5
    expect(ids).to eq([maverick.id, bronco.id, wrangler.id])

    get_json '/cars', sort: 'make,-year', limit: 5
    expect(ids).to eq([maverick.id, bronco.id, wrangler.id])
  end

  it 'pages through with cursors, without skips or repeats' do
    get_json '/cars', sort: '-year'
    first_page = ids
    get_json '/cars', sort: '-year', cursor: json['meta']['next_cursor']

    expect(first_page + ids).to eq([maverick.id, bronco.id, wrangler.id])
    expect(json['meta']['next_cursor']).to be_nil
  end

  it 'pages with offsets when page is sent, and counts when asked' do
    get_json '/cars', page: 2, count: true

    expect(ids).to eq([wrangler.id])
    expect(json['meta']).to eq('limit' => 2, 'page' => 2, 'next_page' => nil, 'total_count' => 3, 'total_pages' => 2)
  end

  it 'reports bad parameters as 400 invalid_data' do
    get_json '/cars', year: { gte: 'new' }, color: 'red', limit: 50, sort: 'vin', cursor: 'junk', year_from: 1
    expect(last_response.status).to eq(400)
    expect(json['error']['details'].map { |d| [d['field'], d['error']] }).to contain_exactly(
      %w[year[gte] invalid], %w[color unknown_attribute], %w[year_from unknown_attribute],
      %w[limit out_of_range], %w[sort invalid], %w[cursor invalid]
    )

    get_json '/cars', year: 2020
    expect(json['error']['details']).to eq([{ 'field' => 'year', 'error' => 'operator_required', 'message' => 'year needs an operator: gte, lte' }])

    get_json '/cars', year: { eq: 2020 }
    expect(json['error']['details'].first['field']).to eq('year[eq]')
  end

  it 'rejects a cursor made for another sort' do
    get_json '/cars', sort: '-year'
    get_json '/cars', sort: 'year', cursor: json['meta']['next_cursor']

    expect(last_response.status).to eq(400)
  end

  it 'accepts the same search as a JSON body with POST /cars/search' do
    json_request :post, '/cars/search', search: { make: 'Jeep' }
    expect(ids).to eq([wrangler.id])
  end

  it 'supports offset-only pagination with counts always on' do
    get_json '/notes', page: 3

    expect(json['notes']).to eq([{ 'id' => wrangler.id, 'make' => 'Jeep' }])
    expect(json['meta']).to include('page' => 3, 'total_count' => 3, 'total_pages' => 3)
  end
end
