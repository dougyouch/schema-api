# frozen_string_literal: true

RSpec.describe SchemaApi::Graphql::InputTypeBuilder do
  def arguments(controller, nested = nil)
    definition = controller.schema_api_definition.finalize!
    root = described_class.new.input_type(definition.schema_class, 'Car', root: true)
    type = nested ? root.arguments[nested].type.unwrap : root
    type.arguments.keys
  end

  it 'offers id on has_many items matched by id, and leaves it off the root' do
    expect(arguments(FleetCarsController)).not_to include('id')
    expect(arguments(FleetCarsController, 'owners')).to include('id', '_destroy')
  end

  it 'has no input type for a schema with nothing writable' do
    definition = NotesController.schema_api_definition.finalize!

    expect(described_class.new.input_type(definition.schema_class, 'Note', root: true)).to be_nil
  end
end
