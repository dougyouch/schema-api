# frozen_string_literal: true

module SchemaApi
  # Macros added to a controller that includes SchemaApi.
  module ClassMethods
    # The standard actions, all defined unless schema(actions:) says otherwise.
    CRUD_ACTIONS = %i[index show create update destroy].freeze
    # Actions defined by bulk.
    BULK_ACTIONS = %i[bulk_create bulk_update bulk_upsert].freeze
    # Steps that take before_, after_ and around_ callbacks.
    CALLBACK_STEPS = %i[validation assign save].freeze

    # Declares the resource's schema.
    #
    # @example
    #   schema do ... end                                  # model and root key from the controller name
    #   schema(AuthDB::User) do ... end                    # explicit model
    #   schema(UserSchema, model: AuthDB::User) do ... end # extend a shared schema class
    #
    # @param source [Class, nil] a model class or a schema class
    # @param options [Hash]
    # @option options [Class, String] :model the model, when source is a schema class or the name differs
    # @option options [Symbol, String] :root root key for one resource
    # @option options [Symbol, String] :collection_root root key for a list
    # @option options [String] :class_name name of the schema class constant
    # @option options [Array<Symbol>] :actions which CRUD actions to define
    # @option options [Boolean, Symbol, Proc] :touch how the root is bumped when children change
    # @yield attribute declarations, evaluated in the schema class
    # @return [Class] the schema class
    def schema(source = nil, **options, &)
      definition = own_schema_api_definition
      schema_class = definition.define_schema(source, options, &)
      define_resource_reader(definition.root)
      private(*(CRUD_ACTIONS - options[:actions])) if options[:actions]
      SchemaApi.register(self)
      schema_class
    end

    # Declares the filters and sorts index accepts. See {Search::Definition}.
    # @return [Search::Definition]
    def search(&)
      search = own_schema_api_definition.search
      search.instance_eval(&)
      public :search
      search
    end

    # Chooses the pagination modes, limits and counting. See {Pagination::Config}.
    # @param modes [Symbol, Array<Symbol>] :cursor, :offset or both
    # @param limit [Hash] default: and max:
    # @param count [Boolean, Symbol] true, :optional or false
    # @return [void]
    def paginate(modes = :cursor, limit: {}, count: false)
      own_schema_api_definition.pagination = Pagination::Config.new(modes, limit: limit, count: count)
    end

    # Enables upsert, matching records by these schema fields within resource_scope.
    # @param fields [Array<Symbol>]
    # @return [void]
    def upsert_key(*fields)
      own_schema_api_definition.upsert_keys = fields.flatten.map(&:to_sym)
      public :upsert
      public :bulk_upsert if public_method_defined?(:bulk_create)
    end

    # Enables the bulk actions.
    # @param max [Integer] most items in one request
    # @param atomic [Boolean] all-or-nothing instead of best effort
    # @param status [Symbol, Integer, Proc] response status, or a proc given the {BulkResult}
    # @param key [Symbol] schema field bulk_update matches records by
    # @return [void]
    def bulk(max: 100, atomic: false, status: :ok, key: :id)
      own_schema_api_definition.bulk = BulkConfig.new(max: max, atomic: atomic, status: status, key: key)
      public :bulk_create, :bulk_update
      public :bulk_upsert if own_schema_api_definition.upsert_keys.any?
    end

    # Adds input validations that need the controller (current user, tenant, database).
    # Each method or block is called with the {WriteContext}; add errors to context.errors.
    # @return [void]
    def validate_input(*names, **options, &block)
      own_schema_api_definition.callbacks.add(:validate, :validation, names, options, block)
    end

    CALLBACK_STEPS.each do |step|
      %i[before after around].each do |kind|
        define_method(:"#{kind}_#{step}") do |*names, **options, &block|
          own_schema_api_definition.callbacks.add(kind, step, names, options, block)
        end
      end
    end

    # Runs after a write's transaction commits.
    # @return [void]
    def after_commit(*names, **options, &block)
      own_schema_api_definition.callbacks.add(:after, :commit, names, options, block)
    end

    # @return [Definition, nil] this controller's definition, or the one it inherits
    def schema_api_definition
      return @schema_api_definition if @schema_api_definition

      superclass.schema_api_definition if superclass.respond_to?(:schema_api_definition)
    end

    private

    # this controller's own definition, copied from the parent's the first time a macro changes it
    def own_schema_api_definition
      return @schema_api_definition if @schema_api_definition

      @schema_api_definition = schema_api_definition&.copy_for(self) || Definition.new(self)
    end

    # car => resource, so actions and hooks can say car instead of resource
    def define_resource_reader(root)
      return if method_defined?(root) || private_method_defined?(root)

      define_method(root) { resource }
      private root
    end
  end
end
