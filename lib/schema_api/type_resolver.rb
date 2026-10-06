# frozen_string_literal: true

module SchemaApi
  # Maps a model attribute's ActiveRecord type to a schema-model type and options.
  class TypeResolver
    # ActiveRecord type => schema type
    TYPES = {
      integer: :integer,
      big_integer: :integer,
      string: :string,
      text: :string,
      uuid: :string,
      citext: :string,
      boolean: :boolean,
      float: :float,
      decimal: :decimal,
      datetime: :time,
      timestamp: :time,
      timestamptz: :time,
      time: :time,
      date: :date,
      json: :hash,
      jsonb: :hash
    }.freeze

    # @param model [Class] an ActiveRecord model
    def initialize(model)
      @model = model
    end

    # @param column [Symbol, String]
    # @return [Array(Symbol, Hash), nil] [schema type, extra options], nil when the model has no such attribute
    def resolve(column)
      column = column.to_s
      return unless @model.attribute_names.include?(column)
      return [:string, { enum_values: @model.defined_enums[column].keys }] if @model.defined_enums.key?(column)

      ar_type = @model.attribute_types[column]
      return array_type(ar_type) if ar_type.respond_to?(:subtype)

      [TYPES.fetch(ar_type.type, :string), {}]
    end

    # @param column [Symbol, String]
    # @return [Boolean] whether the attribute is a json/jsonb column
    def json?(column)
      column = column.to_s
      @model.attribute_names.include?(column) && %i[json jsonb].include?(@model.attribute_types[column].type)
    end

    private

    def array_type(ar_type)
      [:array, { data_type: TYPES.fetch(ar_type.subtype.type, :string) }]
    end
  end
end
