# frozen_string_literal: true

module SchemaApi
  # Plans a write without changing anything: matches nested items to existing children,
  # decides what's created, updated and removed, looks up belongs_to keys, and builds JSON
  # column values. Every problem is collected, then raised together.
  #
  # PUT replaces and PATCH merges at every level; see DESIGN.md, "Write semantics".
  class TreePlanner
    # What plan_item needs about the has_many list being planned.
    # @api private
    ListState = Struct.new(:node, :field, :plan, :matcher, :seen)

    # @param reference_lookup [#call] (belongs_to field, key value) => record or nil, within its scope
    def initialize(reference_lookup)
      @reference_lookup = reference_lookup
      @invalid = ErrorList.new
      @missing_references = ErrorList.new
    end

    # @param record [ActiveRecord::Base]
    # @param schema [Schema::Model]
    # @param creating [Boolean]
    # @param partial [Boolean]
    # @return [TreeNode]
    # @raise [InvalidData] for duplicate keys, unknown ids, changed create-only fields, forbidden removals
    # @raise [ValidationError] for belongs_to keys that don't exist in their scope
    def plan(record, schema, creating:, partial:)
      node = plan_node(schema, record, creating: creating, partial: partial, path: nil)
      raise InvalidData.new(nil, details: @invalid.to_a + @missing_references.to_a) unless @invalid.empty?
      raise ValidationError.new(nil, details: @missing_references.to_a) unless @missing_references.empty?

      node
    end

    private

    def plan_node(schema, record, creating:, partial:, path:)
      node = TreeNode.new(schema: schema, record: record, creating: creating, partial: partial, path: path)
      schema.class.api_fields.each do |field|
        plan_field(node, field) if touched?(node, field)
      end
      node
    end

    # whether this write changes the field: PATCH only what was sent, PUT everything writable
    def touched?(node, field)
      return false unless planned?(node, field)

      sent = field.set_in?(node.schema)
      return sent if node.partial?
      return true unless field.reference_key?

      sent || reference_field(node, field).reference[:on_put_missing] == :nullify
    end

    # scalars are written by the mappings; belongs_to objects and _destroy flags never are
    def planned?(node, field)
      return false if field.belongs_to? || field.destroy_flag?
      return false unless field.association? || field.reference_key? || field.values_of

      field.input?(node.creating?)
    end

    def plan_field(node, field)
      if field.reference_key?
        plan_reference(node, field)
      elsif field.values_of
        node.value_lists[field] = Array(node.schema.public_send(field.getter)).uniq
      elsif field.backing == :json
        node.json[field] = json_value(node, field)
      elsif field.has_many?
        plan_many(node, field)
      elsif field.association?
        plan_one(node, field)
      end
    end

    def plan_reference(node, field)
      reference = reference_field(node, field)
      value = node.schema.public_send(field.getter)
      return node.references[reference] = nil if value.nil?

      target = @reference_lookup.call(reference, value)
      return node.references[reference] = target if target

      @missing_references.add(join(node.path, field.name), 'not_found', "#{reference.name.to_s.humanize} #{value} does not exist")
    end

    def plan_many(node, field)
      items = node.schema.public_send(field.getter) || []
      existing = node.creating? ? [] : node.record.public_send(field.model_name).to_a
      state = ListState.new(node, field, TreeNode::AssociationPlan.new(field, [], []), ChildMatcher.new(field, existing), {})
      items.each_with_index do |item, index|
        plan_item(state, item, join(node.path, "#{field.name}[#{index}]")) if item
      end
      add_unsent_removals(node, field, state.plan, existing, state.seen)
      check_removals_allowed(node, field, state.plan)
      node.associations << state.plan
    end

    def plan_item(state, item, path)
      key = state.matcher.key_for(item)
      return add_duplicate_key(state, path) if key && state.seen.key?(key)

      child = state.matcher.find(item)
      state.seen[key] = child if key
      return plan_removal(state, child, key, path) if item.respond_to?(:_destroy) && item._destroy
      return state.plan.items << plan_existing(state.node, item, child, path) if child
      return add_child_not_found(state, key, path) if key && state.matcher.primary_key?

      state.plan.items << plan_node(item, nil, creating: true, partial: false, path: path)
    end

    def plan_removal(state, child, key, path)
      return state.plan.removals << child if child

      add_child_not_found(state, key, path) if key && state.matcher.primary_key?
    end

    def add_duplicate_key(state, path)
      @invalid.add(path, 'duplicate_key', "#{state.field.name.to_s.humanize} has the same key more than once")
    end

    def add_child_not_found(state, key, path)
      @invalid.add(path, 'not_found', "#{state.field.name.to_s.humanize.singularize} #{key.join(', ')} does not exist")
    end

    def plan_existing(node, item, child, path)
      @invalid.concat(CreateOnlyCheck.details(item, child, path))
      plan_node(item, child, creating: false, partial: node.partial?, path: path)
    end

    # PUT: the list is the whole collection, so children it doesn't mention are removed
    def add_unsent_removals(node, field, plan, existing, seen)
      return if node.partial? && field.patch_mode != :replace

      kept = seen.values.compact
      plan.removals.concat(existing.reject { |child| kept.include?(child) || plan.removals.include?(child) })
    end

    # on_remove: :error means clients can't remove children, whether by leaving them out or by _destroy
    def check_removals_allowed(node, field, plan)
      return if field.on_remove != :error || plan.removals.empty?

      @invalid.add(join(node.path, field.name), 'remove_not_allowed', "#{field.name.to_s.humanize} can't be removed")
    end

    def plan_one(node, field)
      child = node.schema.public_send(field.getter)
      existing = node.creating? ? nil : node.record.public_send(field.model_name)
      plan = TreeNode::AssociationPlan.new(field, [], [])
      path = join(node.path, field.name)
      if child.nil?
        plan.removals << existing if existing
        check_removals_allowed(node, field, plan)
      elsif existing
        plan.items << plan_existing(node, child, existing, path)
      else
        plan.items << plan_node(child, nil, creating: true, partial: false, path: path)
      end
      node.associations << plan
    end

    # PUT replaces the column; PATCH deep-merges the fields sent into what's stored. Lists are replaced.
    def json_value(node, field)
      value = node.schema.public_send(field.getter)
      return value&.map { |child| json_hash(child) } if field.has_many?
      return nil if value.nil?
      return json_hash(value) unless node.partial?

      (node.record.public_send(field.model_name) || {}).deep_stringify_keys.deep_merge(json_hash(value, only_set: true))
    end

    def json_hash(schema, only_set: false)
      schema.as_json(only_set: only_set).deep_stringify_keys
    end

    def reference_field(node, field)
      node.schema.class.api_field(field.reference_for)
    end

    def join(path, name)
      path ? "#{path}.#{name}" : name.to_s
    end
  end
end
