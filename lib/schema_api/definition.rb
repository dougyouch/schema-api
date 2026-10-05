# frozen_string_literal: true

module SchemaApi
  # Everything a controller declared: the schema, naming, search, pagination, upsert and
  # bulk settings, touch behavior and callbacks. Finalized once, on first use.
  class Definition
    # @return [Class] the controller
    attr_reader :controller
    # @return [Naming, nil]
    attr_reader :naming
    # @return [Class, nil] the schema class
    attr_reader :schema_class
    # @return [Search::Definition]
    attr_accessor :search
    # @return [Pagination::Config]
    attr_accessor :pagination
    # @return [Array<Symbol>] upsert key fields
    attr_accessor :upsert_keys
    # @return [BulkConfig]
    attr_accessor :bulk
    # @return [Boolean, Symbol, Proc] see {Persistence#touch_resource}
    attr_accessor :touch
    # @return [CallbackChain]
    attr_reader :callbacks

    # @param controller [Class]
    def initialize(controller)
      @controller = controller
      @search = Search::Definition.new
      @pagination = Pagination::Config.new
      @upsert_keys = []
      @bulk = BulkConfig.new
      @touch = true
      @callbacks = CallbackChain.new
      @mutex = Mutex.new
    end

    # A copy for a subclass controller, so its macros don't change the parent's settings.
    # @param controller [Class]
    # @return [Definition]
    def copy_for(controller)
      copy = dup
      copy.instance_variable_set(:@controller, controller)
      copy.instance_variable_set(:@callbacks, callbacks.dup)
      copy.search = search.dup
      copy.instance_variable_set(:@mutex, Mutex.new)
      copy
    end

    # Builds the schema class. See {ClassMethods#schema}.
    # @return [Class]
    def define_schema(source, options, &)
      schema_source = source if source.is_a?(Class) && source.include?(::Schema::Model)
      model = options[:model] || (source unless schema_source)
      @naming = Naming.new(controller, model: model, root: options[:root], collection_root: options[:collection_root])
      @touch = options.fetch(:touch, true)
      class_name = options[:class_name] || naming.schema_class_name
      @schema_class = SchemaClassBuilder.new(controller, class_name, schema_source).build(&)
      @finalized = false
      @schema_class
    end

    # Resolves model attributes, nested models and mappings. Safe to call more than once.
    # @return [self]
    def finalize!
      raise DefinitionError, "#{controller.name} has no schema; declare one with schema do ... end" unless schema_class

      @mutex.synchronize do
        next if @finalized

        SchemaFinalizer.new(schema_class, model, path: controller.name).finalize!
        search.finalize!(schema_class, model)
        @includes = IncludesBuilder.new(schema_class).build
        @finalized = true
      end
      self
    end

    # @return [Class] the ActiveRecord model
    def model
      naming.model
    end

    # @return [String]
    def root
      naming.root
    end

    # @return [String]
    def collection_root
      naming.collection_root
    end

    # @return [Hash] the eager-loading tree for the schema's associations
    def includes
      finalize!
      @includes
    end
  end
end
