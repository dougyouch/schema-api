# frozen_string_literal: true

module SchemaApi
  # One record in a write plan: its input, the existing record (nil for a nested create),
  # and what to do with its associations, references, JSON columns and value lists.
  class TreeNode
    # One association's planned changes.
    #
    # @!attribute field
    #   @return [Field]
    # @!attribute items
    #   @return [Array<TreeNode>] children to create or update
    # @!attribute removals
    #   @return [Array<ActiveRecord::Base>] children to remove
    AssociationPlan = Struct.new(:field, :items, :removals)

    # @return [Schema::Model]
    attr_reader :schema
    # @return [ActiveRecord::Base, nil]
    attr_reader :record
    # @return [String, nil]
    attr_reader :path
    # @return [Array<AssociationPlan>]
    attr_reader :associations
    # @return [Hash{Field => ActiveRecord::Base, nil}] belongs_to field => record to reference
    attr_reader :references
    # @return [Hash{Field => Object}] JSON-backed field => column value
    attr_reader :json
    # @return [Hash{Field => Array}] values_of field => values
    attr_reader :value_lists

    # @param schema [Schema::Model]
    # @param record [ActiveRecord::Base, nil]
    # @param creating [Boolean]
    # @param partial [Boolean]
    # @param path [String, nil]
    def initialize(schema:, record:, creating:, partial:, path:)
      @schema = schema
      @record = record
      @creating = creating
      @partial = partial
      @path = path
      @associations = []
      @references = {}
      @json = {}
      @value_lists = {}
    end

    # @return [Boolean]
    def creating?
      @creating
    end

    # @return [Boolean] PATCH semantics for this node
    def partial?
      @partial
    end
  end
end
