# frozen_string_literal: true

module SchemaApi
  # Finds a nested resource's parent from the route, for controllers that declare
  # {ClassMethods#parent}. resource_scope is then the parent's association.
  module ParentLookup
    private

    # @return [ActiveRecord::Base]
    # @raise [ActiveRecord::RecordNotFound] when the parent isn't in its scope
    def parent_resource
      @parent_resource ||= parent_scope.find(params[schema_api.parent.param])
    end

    # @return [ActiveRecord::Relation] the parents the caller may use
    def parent_scope
      scope = schema_api.parent.scope
      scope.is_a?(Proc) ? instance_exec(&scope) : send(scope)
    end

    # @return [Symbol] the parent's has_many for this resource
    def parent_association
      schema_api.parent.association || inferred_parent_association
    end

    def inferred_parent_association
      reflections = parent_resource.class.reflect_on_all_associations(:has_many).select { |r| r.klass == resource_model }
      return reflections.first.name if reflections.one?

      raise DefinitionError,
            "#{self.class.name}: #{parent_resource.class} has #{reflections.size} has_many for #{resource_model}; " \
            'pass association: to parent'
    end
  end
end
