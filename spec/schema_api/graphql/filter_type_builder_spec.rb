# frozen_string_literal: true

RSpec.describe SchemaApi::Graphql::FilterTypeBuilder do
  it 'refuses filters whose GraphQL names collide' do
    search = SchemaApi::Search::Definition.new
    search.filter(:'owners.person_id')
    search.filter(:owners_person_id, :integer) { |scope, _value| scope }

    expect { described_class.new(search, 'Car') }
      .to raise_error(SchemaApi::DefinitionError, /two filters have the same GraphQL name/)
  end
end
