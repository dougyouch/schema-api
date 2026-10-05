# frozen_string_literal: true

module SchemaApi
  # Works out a resource's model, root keys and schema class name. Defaults come from the
  # controller name, because the controller is the API: UsersController is `user`/`users`
  # whatever the model or table is called.
  class Naming
    # @param controller [Class]
    # @param model [Class, String, nil] the model, or its name, when it isn't the controller name singularized
    # @param root [Symbol, String, nil]
    # @param collection_root [Symbol, String, nil]
    def initialize(controller, model: nil, root: nil, collection_root: nil)
      @controller = controller
      @model = model
      @root = root
      @collection_root = collection_root
    end

    # @return [String] e.g. "car"
    def root
      (@root || resource_name.singularize).to_s
    end

    # @return [String] e.g. "cars"
    def collection_root
      return @collection_root.to_s if @collection_root
      return root.pluralize if @root

      resource_name
    end

    # @return [Class] the ActiveRecord model
    # @raise [DefinitionError] when no model is given and none matches the controller name
    def model
      @model = constantize(@model || resource_name.singularize.camelize) unless @model.is_a?(Class)
      @model
    end

    # @return [String] e.g. "CarSchema"
    def schema_class_name
      "#{root.camelize}Schema"
    end

    private

    # "Admin::CarsController" => "cars"
    def resource_name
      @controller.name.demodulize.delete_suffix('Controller').underscore
    end

    def constantize(name)
      name.to_s.constantize
    rescue NameError
      raise DefinitionError, "#{@controller.name}: no model named #{name}; pass it to schema, e.g. schema(#{name})"
    end
  end
end
