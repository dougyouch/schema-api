# frozen_string_literal: true

RSpec.describe 'small helpers' do
  it 'formats times' do
    time = Time.utc(2026, 1, 2, 3, 4, 5.5r)

    expect(SchemaApi::TimeFormatter.format(time, :iso8601)).to eq('2026-01-02T03:04:05Z')
    expect(SchemaApi::TimeFormatter.format(time, :iso8601_usec)).to eq('2026-01-02T03:04:05.500000Z')
    expect(SchemaApi::TimeFormatter.format(time, :unix)).to eq(time.to_i)
    expect(SchemaApi::TimeFormatter.format(time, lambda(&:year))).to eq(2026)
  end

  it 'builds default error messages' do
    list = SchemaApi::ErrorList.new.add('owners[0].person_id', :not_allowed).add(nil, 'invalid')

    expect(list.map { |detail| detail[:message] }).to eq(['Person is not allowed', 'Value is invalid'])
  end

  it 'types array columns from their subtype' do
    model = Struct.new(:attribute_names, :defined_enums, :attribute_types)
                  .new(['tags'], {}, { 'tags' => Struct.new(:subtype).new(Struct.new(:type).new(:integer)) })

    expect(SchemaApi::TypeResolver.new(model).resolve(:tags)).to eq([:array, { data_type: :integer }])
  end

  it 'finalizes every registered controller' do
    expect(SchemaApi.finalize_all!).to include(CarsController, UsersController)
  end
end
