# frozen_string_literal: true

module SchemaApi
  module Graphql
    # Adds one resource's mutations, each for an action the controller has. They return the
    # written record as the query fields render it.
    #
    #   create_user(user: UserInput!): User                 # create
    #   update_user(id: ID!, user: UserInput!): User        # PATCH: only what's sent changes; null clears
    #   upsert_user(user: UserInput!): User                 # upsert, merging into a match
    #   delete_user(id: ID!): User                          # destroy; the record as it was
    class MutationFields
      # @param resource [Resource]
      # @param inputs [InputTypeBuilder]
      def initialize(resource, inputs)
        @resource = resource
        @root = resource.definition.root.to_sym
        @input_type = inputs.input_type(resource.definition.schema_class, resource.type_name, root: true)
      end

      # @param mutation_type [Class] the Mutation type
      # @return [void]
      def add_to(mutation_type)
        if @input_type
          add_create(mutation_type) if @resource.action?('create')
          add_update(mutation_type) if @resource.action?('update')
          add_upsert(mutation_type) if @resource.action?('upsert')
        end
        add_delete(mutation_type) if @resource.action?('destroy')
      end

      private

      def add_create(mutation_type)
        add_field(mutation_type, :create, with_input: true) { |runner, data| runner.create(data) }
      end

      def add_update(mutation_type)
        add_field(mutation_type, :update, with_id: true, with_input: true) { |runner, data, id| runner.update(id, data) }
      end

      def add_upsert(mutation_type)
        add_field(mutation_type, :upsert, with_input: true) { |runner, data| runner.upsert(data) }
      end

      def add_delete(mutation_type)
        add_field(mutation_type, :delete, with_id: true) { |runner, _data, id| runner.destroy(id) }
      end

      # the field, its id and input arguments, and a resolver that calls the block with the
      # runner, the input as a string-keyed hash, and the id
      def add_field(mutation_type, verb, with_id: false, with_input: false, &call)
        name = "#{verb}_#{@root}"
        field = mutation_type.field(name, @resource.object_type, null: true, camelize: false, resolver_method: :"resolve_#{name}")
        field.argument(:id, ::GraphQL::Types::ID, required: true) if with_id
        field.argument(@root, @input_type, required: true, camelize: false) if with_input
        define_resolver(mutation_type, name, call)
      end

      def define_resolver(mutation_type, name, call)
        resource = @resource
        root = @root
        mutation_type.define_method(:"resolve_#{name}") do |id: nil, **arguments|
          call.call(resource.runner(context), arguments[root].to_h.deep_stringify_keys, id)
        end
      end
    end
  end
end
