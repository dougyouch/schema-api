# frozen_string_literal: true

module SchemaApi
  # The write pipeline every write action runs: check, validate, then in one transaction
  # lock, assign, save and touch; then after-commit callbacks. Each step is a method to
  # override, and each is given the {WriteContext}.
  module Persistence
    private

    # Writes one resource and its nested records.
    # @param record [ActiveRecord::Base] found or built
    # @param input [Schema::Model]
    # @param partial [Boolean] PATCH semantics (ignored when creating)
    # @return [ActiveRecord::Base] the record, reloaded
    def write_resource!(record, input, partial: false)
      context = WriteContext.new(action: action_name.to_sym, record: record, input: input, partial: partial)
      check_input!(context)
      schema_api.callbacks.run(self, :validation, context) { validate_input!(context) }
      resource_transaction { save_tree!(context) }
      record.reload
      after_resource_commit(context)
      record
    end

    def save_tree!(context)
      check_lock!(context)
      schema_api.callbacks.run(self, :assign, context) { assign_resource(context) }
      schema_api.callbacks.run(self, :save, context) { save_resource!(context) }
      touch_resource(context.record, context.changes) if context.changes.any?
    end

    # Parsing errors, id mismatch, changed create-only fields, missing required lock.
    # @raise [InvalidData]
    def check_input!(context)
      details = InputChecker.new(context).details
      raise InvalidData.new("#{resource_label} has invalid data", details: details) if details.any?
    end

    # Schema validations at every level (against the merged result for PATCH), then validate_input methods.
    # @raise [ValidationError]
    def validate_input!(context)
      target = context.partial? ? PatchMerger.new.merge(present_for_merge(context.record), context.input) : context.input
      details = ErrorCollector.new.validation_details(target, context.validation_context)
      schema_api.callbacks.validate(self, context)
      details.concat(context.errors.to_a)
      raise ValidationError.new("#{resource_label} is invalid", details: details) if details.any?
    end

    def present_for_merge(record)
      Presenter.new.present(record, resource_schema_class)
    end

    # Locks the row and compares lock: fields that were sent with the stored values.
    # @raise [StaleResource]
    def check_lock!(context)
      return if context.creating?

      fields = resource_schema_class.api_fields.select { |field| field.lock? && field.set_in?(context.input) }
      return if fields.empty?

      context.record.lock!
      stale = fields.reject do |field|
        ValueComparer.same?(context.input.public_send(field.getter), context.record.public_send(field.model_name))
      end
      return if stale.empty?

      details = stale.map { |field| stale_detail(field) }
      raise StaleResource.new("#{resource_label} has changed since it was read", details: details)
    end

    def stale_detail(field)
      { field: field.name.to_s, error: 'stale', message: "#{field.name.to_s.humanize} doesn't match the stored value" }
    end

    # Plans the write: nested matching, removals, belongs_to lookups.
    def assign_resource(context)
      planner = TreePlanner.new(->(field, value) { find_reference(field, value) })
      context.plan = planner.plan(context.record, context.input, creating: context.creating?, partial: context.partial?)
    end

    # Saves the root and nested records.
    def save_resource!(context)
      TreeExecutor.new(context.changes).execute(context.plan)
    end

    # Bumps the root after any real change in the tree. Called only when something changed.
    # The default touches the record unless the root was already saved with changes;
    # schema(touch:) can turn it off or call another method.
    # @param record [ActiveRecord::Base]
    # @param changes [TreeChanges]
    def touch_resource(record, changes)
      touch = schema_api.touch
      case touch
      when true then record.touch unless changes.root_changed?
      when Proc then instance_exec(record, changes, &touch)
      when Symbol, String then record.respond_to?(touch) ? record.public_send(touch) : send(touch, record, changes)
      end
    end

    def destroy_resource!(record)
      record.destroy!
    end

    def resource_transaction(&)
      resource_model.transaction(requires_new: true, &)
    end

    # after_commit callbacks run now, or after the outer transaction when bulk is atomic
    def after_resource_commit(context)
      return @schema_api_deferred_commits << context if @schema_api_deferred_commits

      schema_api.callbacks.run(self, :commit, context) { nil }
    end

    def deferring_commits
      @schema_api_deferred_commits = []
      yield
      contexts = @schema_api_deferred_commits
      @schema_api_deferred_commits = nil
      contexts
    ensure
      @schema_api_deferred_commits = nil
    end
  end
end
