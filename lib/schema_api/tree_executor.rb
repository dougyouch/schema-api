# frozen_string_literal: true

module SchemaApi
  # Carries out a {TreePlanner} plan: assigns and saves each record (parent before
  # children, so children can take its id), removes children, syncs value lists, and
  # records what changed. Runs inside the write's transaction.
  class TreeExecutor
    # @param changes [TreeChanges]
    # @param server_value [#call] (field, record) => value for fields declared with set:
    def initialize(changes, server_value)
      @changes = changes
      @server_value = server_value
    end

    # @param node [TreeNode] the root node
    # @return [ActiveRecord::Base] the root record
    def execute(node)
      execute_node(node, nil, nil)
    end

    private

    def execute_node(node, parent, field)
      record = node.record || parent.association(field.model_name).build
      assign(node, record)
      save!(record, node)
      track(node, record)
      node.associations.each { |plan| execute_association(plan, record, node) }
      node.value_lists.each { |values_field, values| sync_values(record, values_field, values, node) }
      record
    end

    def assign(node, record)
      mappings = node.schema.class.api_mappings
      mapping = (node.partial? ? mappings.patch : mappings.input).new
      mapping.creating = node.creating?
      mapping.map(node.schema, record)
      node.references.each { |field, target| record.public_send(:"#{field.model_name}=", target) }
      node.json.each { |field, value| record.public_send(:"#{field.model_name}=", value) }
      assign_server_fields(node, record)
    end

    # set: fields are filled on create, and (unless on: :create) whenever the record has other
    # changes, so a write that changes nothing still changes nothing
    def assign_server_fields(node, record)
      fields = node.schema.class.api_fields.select(&:server_value)
      return if fields.empty?

      changed = node.creating? || record.changed?
      fields.each do |field|
        next unless node.creating? || (field.set_on == :save && changed)

        record.public_send(:"#{field.column}=", @server_value.call(field, record))
      end
    end

    def save!(record, node)
      record.save!
    rescue ActiveRecord::RecordInvalid
      raise ValidationError.new("#{record.class.model_name.human} is invalid",
                                details: ModelErrors.new(record, node.schema.class, node.path).details)
    rescue ActiveRecord::RecordNotUnique
      raise Conflict.new("#{record.class.model_name.human} conflicts with an existing record",
                         details: [{ field: node.path, error: 'taken', message: 'A record with the same unique values exists' }])
    end

    def track(node, record)
      if node.creating?
        @changes.add(:created, node.path)
      elsif record.saved_changes.any?
        @changes.add(:updated, node.path)
      end
    end

    def execute_association(plan, record, node)
      plan.items.each { |child| execute_node(child, record, plan.field) }
      plan.removals.each { |child| remove(child, plan.field, record) }
      @changes.add(:removed, join(node.path, plan.field.name)) if plan.removals.any?
    end

    def remove(child, field, record)
      case field.on_remove
      when :delete then child.delete
      when :nullify then child.update!(record.class.reflect_on_association(field.model_name).foreign_key => nil)
      else child.destroy!
      end
    end

    def sync_values(record, field, values, node)
      association = field.values_of[:association]
      attribute = field.values_of[:field]
      existing = record.public_send(association).to_a
      stale = existing.reject { |child| values.include?(child.public_send(attribute)) }
      missing = values - existing.map(&attribute)
      stale.each(&:destroy!)
      missing.each { |value| record.association(association).build(attribute => value).save! }
      @changes.add(:updated, join(node.path, field.name)) if stale.any? || missing.any?
    end

    def join(path, name)
      path ? "#{path}.#{name}" : name.to_s
    end
  end
end
