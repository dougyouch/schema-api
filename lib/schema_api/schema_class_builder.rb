# frozen_string_literal: true

module SchemaApi
  # Creates a controller's schema class: a new Schema::All class, or a subclass of a shared
  # schema so the controller's block can add to it without changing it, set as a constant
  # of the controller.
  class SchemaClassBuilder
    # @param controller [Class]
    # @param class_name [String]
    # @param base_class [Class, nil] a shared schema class to extend
    def initialize(controller, class_name, base_class = nil)
      @controller = controller
      @class_name = class_name
      @base_class = base_class
    end

    # @yield attribute declarations, evaluated in the schema class
    # @return [Class]
    def build(&block)
      kls = new_schema_class
      kls.include(ResourceSchema)
      @controller.send(:remove_const, @class_name) if @controller.const_defined?(@class_name, false)
      @controller.const_set(@class_name, kls)
      kls.class_eval(&block) if block
      kls
    end

    private

    def new_schema_class
      return Class.new(@base_class) if @base_class

      Class.new { include ::Schema::All }
    end
  end
end
