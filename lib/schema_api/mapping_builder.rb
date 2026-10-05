# frozen_string_literal: true

module SchemaApi
  # Compiles a schema class's mappable mappings from its field options:
  #
  # - output: model -> schema, the rendered scalar fields
  # - input: schema -> model, every writable scalar (create and PUT); write-only ones only when sent
  # - patch: schema -> model, only the writable scalars that were sent (PATCH)
  #
  # Create-only fields are mapped `if: :creating`. Associations are handled by {TreeExecutor}.
  class MappingBuilder
    # The compiled mapping classes of one schema class.
    #
    # @!attribute output
    #   @return [Class]
    # @!attribute input
    #   @return [Class]
    # @!attribute patch
    #   @return [Class]
    Mappings = Struct.new(:output, :input, :patch)

    # @param schema_class [Class]
    def initialize(schema_class)
      @schema_class = schema_class
    end

    # @return [Mappings]
    def build
      Mappings.new(output_mapping, input_mapping(partial: false), input_mapping(partial: true))
    end

    private

    def output_mapping
      fields = @schema_class.api_fields.select(&:output_mapped?)
      new_mapping do
        fields.each do |field|
          field.value_proc ? custom_map(field.name, field.value_proc) : map(field.model_name, field.name)
        end
      end
    end

    def input_mapping(partial:)
      fields = @schema_class.api_fields.select(&:input_mapped?)
      new_mapping do
        attr_accessor :creating

        fields.each do |field|
          conditions = {}
          conditions[:if] = :creating if field.create_only?
          # write-only fields (passwords, secrets) keep their value when PUT leaves them out
          conditions[:if_src] = :"#{field.name}_was_set?" if partial || field.write_only?
          map(field.name, field.model_name, conditions)
        end
      end
    end

    def new_mapping(&)
      Class.new do
        include ::Mappable::Mapping

        class_eval(&)
      end
    end
  end
end
