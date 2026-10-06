# frozen_string_literal: true

RSpec.describe SchemaApi::ClassMethods do
  around do |example|
    registered = SchemaApi.controllers.dup
    example.run
    SchemaApi.controllers.replace(registered)
  end

  it 'gives a subclass its own copy of the settings' do
    parent = Class.new(ActionController::API) do
      include SchemaApi

      def self.name
        'ParentCarsController'
      end

      schema(Car) { model_attribute :id }
      search { filter :id }
    end
    child = Class.new(parent) do
      before_save :audit
      search { filter :vin, :string }
    end

    expect(child.schema_api_definition.search.filters.keys).to eq(%w[id vin])
    expect(parent.schema_api_definition.search.filters.keys).to eq(%w[id])
    expect(child.schema_api_definition.schema_class).to eq(parent.schema_api_definition.schema_class)
    expect(child.schema_api_definition.controller).to eq(child)
  end

  it 'explains a missing model and a missing schema' do
    kls = Class.new(ActionController::API) do
      include SchemaApi

      def self.name
        'WidgetsController'
      end
    end

    expect { kls.schema_api_definition }.not_to raise_error
    kls.paginate(:offset)
    expect { kls.schema_api_definition.finalize! }.to raise_error(SchemaApi::DefinitionError, /WidgetsController has no schema/)

    kls.schema { model_attribute :id }
    expect { kls.schema_api_definition.model }.to raise_error(SchemaApi::DefinitionError, /no model named Widget/)
  end

  it 'rejects unknown pagination modes and filter operators' do
    expect { SchemaApi::Pagination::Config.new(:pages) }.to raise_error(SchemaApi::DefinitionError, /unknown mode pages/)
    expect { SchemaApi::Search::Filter.new(:x, :string, [:like], nil) }.to raise_error(SchemaApi::DefinitionError, /unknown operator like/)
  end
end

RSpec.describe SchemaApi::Search::Definition do
  let(:schema_class) { CarsController.schema_api_definition.finalize!.schema_class }

  it 'only sorts and filters on model attributes of the schema' do
    sorting = described_class.new.tap { |search| search.sort(:label) }
    expect { sorting.finalize!(schema_class, Car) }.to raise_error(SchemaApi::UnknownAttributeError, /search sort label/)

    filtering = described_class.new.tap { |search| search.filter(:owners) }
    expect { filtering.finalize!(schema_class, Car) }.to raise_error(SchemaApi::UnknownAttributeError, /search filter owners/)
  end
end
