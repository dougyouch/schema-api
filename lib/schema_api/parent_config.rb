# frozen_string_literal: true

module SchemaApi
  # A nested resource's parent, declared with {ClassMethods#parent}.
  #
  # @!attribute name
  #   @return [Symbol] reader for the parent record, e.g. :organization
  # @!attribute scope
  #   @return [Symbol, Proc] controller method or proc giving the parents the caller may use
  # @!attribute param
  #   @return [Symbol] route parameter holding the parent's id, e.g. :organization_id
  # @!attribute association
  #   @return [Symbol, nil] the parent's has_many for this resource; inferred when nil
  ParentConfig = Struct.new(:name, :scope, :param, :association)
end
