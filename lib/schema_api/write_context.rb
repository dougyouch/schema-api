# frozen_string_literal: true

module SchemaApi
  # What one resource write is working with, passed to every step and callback.
  class WriteContext
    # @return [Symbol] the controller action, e.g. :update
    attr_reader :action
    # @return [ActiveRecord::Base]
    attr_reader :record
    # @return [Schema::Model] the parsed input
    attr_reader :input
    # @return [TreeChanges] what the write created, updated and removed
    attr_reader :changes
    # @return [ErrorList] errors added by validate_input methods
    attr_reader :errors
    # @return [TreeNode, nil] the write plan, set by assign
    attr_accessor :plan

    # @param action [Symbol]
    # @param record [ActiveRecord::Base]
    # @param input [Schema::Model]
    # @param partial [Boolean] PATCH semantics
    def initialize(action:, record:, input:, partial:)
      @action = action
      @record = record
      @input = input
      @creating = record.new_record?
      @partial = partial && !@creating
      @changes = TreeChanges.new
      @errors = ErrorList.new
    end

    # @return [Boolean] true for PATCH on an existing record
    def partial?
      @partial
    end

    # @return [Boolean] true when the record is new
    def creating?
      @creating
    end

    # @return [Symbol] the validation context: :create or :update
    def validation_context
      creating? ? :create : :update
    end
  end
end
