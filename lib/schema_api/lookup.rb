# frozen_string_literal: true

module SchemaApi
  # Finding, building and parsing resources. Override any of these in a controller.
  module Lookup
    private

    # @return [Definition] the controller's finalized definition
    def schema_api
      self.class.schema_api_definition.finalize!
    end

    # @return [Class] the ActiveRecord model
    def resource_model
      schema_api.model
    end

    # @return [Class] the schema class
    def resource_schema_class
      schema_api.schema_class
    end

    # The records this controller can see. Override to scope by tenant or user:
    #
    #   def resource_scope
    #     Car.where(tenant: current_tenant)
    #   end
    #
    # @return [ActiveRecord::Relation]
    def resource_scope
      resource_model.all
    end

    # resource_scope with the schema's eager loading
    # @return [ActiveRecord::Relation]
    def scoped_resources
      includes = schema_api.includes
      includes.empty? ? resource_scope : resource_scope.includes(includes)
    end

    # @return [ActiveRecord::Base]
    # @raise [ActiveRecord::RecordNotFound]
    def find_resource
      scoped_resources.find(params[:id])
    end

    # @return [ActiveRecord::Base] the record for show, update and destroy
    def resource
      @resource ||= find_resource
    end

    # A new record, built through resource_scope so scope conditions (e.g. tenant) are set.
    # @return [ActiveRecord::Base]
    def build_resource
      resource_scope.new
    end

    # @return [Schema::Model] the request body under the root key
    def resource_input
      @resource_input ||= build_input(input_parser(schema_api.root).object)
    end

    # @return [Array<Schema::Model>] the request body under the collection root key
    def resource_inputs
      input_parser(schema_api.collection_root).list(max: schema_api.bulk.max).map { |data| build_input(data) }
    end

    # @param root_key [String]
    # @return [InputParser]
    def input_parser(root_key)
      InputParser.new(request.raw_post, root_key)
    end

    # anything but an object becomes an empty schema with an incompatible error, so it's reported like bad data
    def build_input(data)
      return resource_schema_class.from_hash(data) if data.is_a?(Hash)

      input = resource_schema_class.new
      input.parsing_errors.add(:base, ::Schema::ParsingErrors::INCOMPATIBLE)
      input
    end

    # The records a belongs_to key may point at, from the field's scope: option.
    # @param field [Field] the belongs_to field
    # @return [ActiveRecord::Relation]
    def reference_scope(field)
      scope = field.reference[:scope]
      case scope
      when :all then field.nested_class.schema_model.all
      when Proc then instance_exec(&scope)
      else send(scope)
      end
    end

    # @param field [Field] the belongs_to field
    # @param value [Object] the key sent
    # @return [ActiveRecord::Base, nil]
    def find_reference(field, value)
      reference_scope(field).find_by(field.reference[:key] => value)
    end

    # @param input [Schema::Model]
    # @return [ActiveRecord::Base, nil] the record upsert updates, nil to create one
    def find_resource_for_upsert(input)
      scoped_resources.find_by(upsert_conditions(input))
    end

    # @param inputs [Array<Schema::Model>]
    # @return [Hash{Array => ActiveRecord::Base}] upsert key values => record
    def find_resources_for_upsert(inputs)
      columns = upsert_key_fields.map(&:column)
      first_values = inputs.map { |input| upsert_key_values(input).first }.compact.uniq
      records = scoped_resources.where(columns.first => first_values)
      records.index_by { |record| columns.map { |column| record.public_send(column) } }
    end

    # @return [Array<Field>]
    def upsert_key_fields
      schema_api.upsert_keys.map { |key| resource_schema_class.api_field(key) }
    end

    # @return [Array] the input's upsert key values
    def upsert_key_values(input)
      upsert_key_fields.map { |field| input.public_send(field.getter) }
    end

    def upsert_conditions(input)
      upsert_key_fields.map(&:column).zip(upsert_key_values(input)).to_h
    end
  end
end
