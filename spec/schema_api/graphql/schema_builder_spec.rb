# frozen_string_literal: true

RSpec.describe SchemaApi::Graphql::SchemaBuilder do
  def build(*controllers, max_depth: 15)
    described_class.new(controllers, max_depth: max_depth).build
  end

  it 'limits how deeply a query may nest' do
    schema = build(CarsController, max_depth: 3)
    result = schema.execute('{ cars { nodes { manufacturer { name } } } }', context: {})

    expect(result['errors'].first['message']).to eq('Query has depth of 4, which exceeds max depth of 3')
  end

  it 'leaves out the Mutation type when no controller can write' do
    expect(build(NotesController).mutation).to be_nil
    expect(build(CarsController).mutation.fields.keys).to include('create_car')
  end

  it 'refuses controllers it cannot expose' do
    expect { build }.to raise_error(SchemaApi::DefinitionError, 'graphql_resources: no controllers given')
    expect { build(PingController) }.to raise_error(SchemaApi::DefinitionError, 'PingController has no SchemaApi schema')
    expect { build(CarOwnersController) }
      .to raise_error(SchemaApi::DefinitionError, "CarOwnersController: nested resources aren't supported by GraphQL yet")
  end
end
