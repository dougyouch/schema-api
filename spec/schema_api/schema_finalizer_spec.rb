# frozen_string_literal: true

RSpec.describe SchemaApi::SchemaFinalizer do
  def schema_class(&block)
    Class.new do
      include Schema::All
      include SchemaApi::ResourceSchema

      def self.name
        'TestSchema'
      end

      class_eval(&block)
    end
  end

  def finalize(model = Car, &)
    described_class.new(schema_class(&), model, path: 'Test').finalize!
  end

  it 'types model attributes from the columns and adds enum validations' do
    kls = finalize do
      model_attribute :year
      model_attribute :price
      model_attribute :status
      model_attribute :created_at
      model_attribute :options
    end

    expect(kls.schema.transform_values { |options| options[:type] }).to include(year: :integer, price: :decimal, status: :string,
                                                                                created_at: :time, options: :hash)
    expect(kls.from_hash(status: 'gone').tap(&:valid?).errors.details).to eq(status: [{ error: :inclusion, value: 'gone' }])
  end

  it 'raises for a column the model does not have' do
    expect { finalize { model_attribute :colour } }.to raise_error(SchemaApi::UnknownAttributeError, 'Test.colour: Car has no attribute colour')
  end

  it 'raises for a nested schema that is neither an association nor a json column' do
    expect { finalize { has_one(:engine) { attribute :size, :integer } } }
      .to raise_error(SchemaApi::UnknownAttributeError, 'Test.engine: Car has no association or json column engine')
  end

  it 'requires scope: on a writable belongs_to' do
    expect { finalize { belongs_to(:manufacturer, input: true) { model_attribute :id } } }
      .to raise_error(SchemaApi::MissingScopeError, /Test.manufacturer: belongs_to with input: true needs scope:/)
  end

  it 'raises for a belongs_to the model does not have' do
    expect { finalize { belongs_to(:maker) { model_attribute :id } } }
      .to raise_error(SchemaApi::UnknownAttributeError, 'Test.maker: Car has no belongs_to maker')
  end

  it 'raises for a has_many key the nested schema does not declare' do
    expect { finalize { has_many(:owners, input: true, key: :ssn) { model_attribute :id } } }
      .to raise_error(SchemaApi::DefinitionError, "Test.owners: key ssn isn't an attribute of the nested schema")
  end

  it 'raises for values_of an unknown association' do
    expect { finalize { attribute :tags, :array, values_of: { association: :tags, field: :name } } }
      .to raise_error(SchemaApi::UnknownAttributeError, 'Test.tags: Car has no association tags')
  end

  it 'raises for model_attribute inside a JSON-backed schema' do
    expect { finalize { has_one(:options) { model_attribute :color } } }
      .to raise_error(SchemaApi::UnknownAttributeError, 'Test.options.color: model_attribute needs a type inside a JSON-backed schema')
  end

  it 'refuses to write through has_many :through' do
    through_model = Class.new(ActiveRecord::Base) do
      self.table_name = 'cars'
      has_many :owners, foreign_key: :car_id
      has_many :people, through: :owners, source: :car

      def self.name
        'ThroughCar'
      end
    end

    expect { finalize(through_model) { has_many(:people, input: true) { model_attribute :id } } }
      .to raise_error(SchemaApi::DefinitionError, /has_many :through associations can't be written/)
  end

  it 'gives nested classes the extension when it is included in a shared schema' do
    kls = schema_class { has_many(:owners, input: true) { model_attribute :id } }

    expect(kls::SchemaHasManyOwners).to respond_to(:model_attribute)
  end

  it 'raises when a model attribute is set before finalize' do
    kls = schema_class { model_attribute :year }

    expect { kls.from_hash(year: 1) }.to raise_error(SchemaApi::NotFinalizedError, /TestSchema#year is a model_attribute/)
  end
end
