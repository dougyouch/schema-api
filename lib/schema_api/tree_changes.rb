# frozen_string_literal: true

module SchemaApi
  # The paths a write created, updated and removed. The root's path is "".
  class TreeChanges
    # @return [Array<String>]
    attr_reader :created, :updated, :removed

    def initialize
      @created = []
      @updated = []
      @removed = []
    end

    # @param kind [Symbol] :created, :updated or :removed
    # @param path [String, nil]
    # @return [self]
    def add(kind, path)
      public_send(kind) << path.to_s
      self
    end

    # @return [Boolean] whether anything in the tree changed
    def any?
      !(created.empty? && updated.empty? && removed.empty?)
    end

    # @return [Boolean] whether the root itself was created or saved with changes
    def root_changed?
      created.include?('') || updated.include?('')
    end

    # @return [Hash{Symbol => Array<String>}]
    def paths
      { created: created, updated: updated, removed: removed }
    end
  end
end
