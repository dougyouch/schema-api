# frozen_string_literal: true

RSpec.describe SchemaApi::Graphql::ScalarTypes do
  def field(**options)
    SchemaApi::Field.new(options, nil)
  end

  it 'types values the way the serializer renders them' do
    expect(described_class.for_field(field(type: :integer))).to eq(GraphQL::Types::Int)
    expect(described_class.for_field(field(type: :decimal))).to eq(GraphQL::Types::String)
    expect(described_class.for_field(field(type: :time))).to eq(GraphQL::Types::String)
    expect(described_class.for_field(field(type: :time, format: :unix))).to eq(GraphQL::Types::Int)
    expect(described_class.for_field(field(type: :time, format: :year.to_proc))).to eq(GraphQL::Types::JSON)
  end

  it 'types arrays by their data_type, and anything untyped as JSON' do
    expect(described_class.for_field(field(type: :array, data_type: :string))).to eq([GraphQL::Types::String])
    expect(described_class.for_field(field(type: :array))).to eq([GraphQL::Types::JSON])
    expect(described_class.for_argument(:array, data_type: :integer)).to eq([GraphQL::Types::Int])
  end
end
