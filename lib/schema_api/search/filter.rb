# frozen_string_literal: true

module SchemaApi
  module Search
    # One declared filter: which operators it takes, the type of its values, and the column
    # (or nested association column) it compiles to.
    class Filter
      # Supported operators.
      OPERATORS = %i[eq not_eq in contains starts_with gt gte lt lte null].freeze
      # Operators whose Arel method has another name.
      AREL_METHODS = { gte: :gteq, lte: :lteq }.freeze

      # @return [Symbol]
      attr_reader :name
      # @return [Array<Symbol>]
      attr_reader :ops
      # @return [Symbol, nil]
      attr_reader :type

      # @param name [Symbol, String]
      # @param type [Symbol, nil]
      # @param ops [Array<Symbol>]
      # @param block [Proc, nil]
      def initialize(name, type, ops, block)
        @name = name.to_s
        @type = type
        @ops = ops.map(&:to_sym)
        @block = block
        unknown = @ops - OPERATORS
        raise DefinitionError, "search filter #{name}: unknown operator #{unknown.join(', ')}" if unknown.any?
      end

      # @api private
      def finalize!(schema_class, model)
        @model = model
        field_path = name.split('.')
        return finalize_block(schema_class) if @block
        raise DefinitionError, "search filter #{name}: only one level of nesting is supported" if field_path.size > 2

        if field_path.size == 2
          finalize_nested(schema_class,
                          *field_path)
        else
          finalize_column(schema_class.api_field(field_path.first), model)
        end
      end

      # @return [Symbol, nil] the operator used when a value is sent without one
      def default_op
        return :eq if ops.include?(:eq)

        ops.first if ops.size == 1
      end

      # @param op [Symbol]
      # @return [Array(Symbol, Hash)] schema type and options for this operator's value
      def param_type(op)
        case op
        when :in then [:array, { separator: ',', data_type: type }]
        when :null then [:boolean, {}]
        when :contains, :starts_with then [:string, {}]
        else [type, {}]
        end
      end

      # @param scope [ActiveRecord::Relation]
      # @param op [Symbol]
      # @param value [Object] parsed
      # @param controller [ActionController::Metal] custom filters run in it
      # @return [ActiveRecord::Relation]
      def apply(scope, op, value, controller)
        return controller.instance_exec(scope, value, &@block) if @block

        condition = arel_condition(@table[@column], op, value)
        return scope.where(condition) unless @association

        scope.where(@model.primary_key => @model.unscoped.joins(@association).where(condition).select(@model.primary_key))
      end

      private

      def finalize_block(schema_class)
        @type ||= schema_class.api_field(name)&.type
        raise DefinitionError, "search filter #{name}: give a type, e.g. filter(:#{name}, :string)" unless @type
      end

      def finalize_column(field, model)
        unless field&.column && (field.scalar? || field.reference_key?)
          raise UnknownAttributeError, "search filter #{name}: not a model attribute of the schema"
        end

        @type ||= field.type
        @column = field.column.to_s
        @table = model.arel_table
      end

      def finalize_nested(schema_class, association_name, field_name)
        association = schema_class.api_field(association_name)
        reflection = association&.association? && model_reflection(association)
        raise UnknownAttributeError, "search filter #{name}: #{association_name} isn't a model association" unless reflection

        finalize_column(association.nested_class.api_field(field_name), reflection.klass)
        @association = reflection.name
      end

      def model_reflection(association)
        @model.reflect_on_association(association.model_name) if %i[association reference].include?(association.backing)
      end

      def arel_condition(column, op, value)
        case op
        when :contains then column.matches("%#{ActiveRecord::Base.sanitize_sql_like(value)}%")
        when :starts_with then column.matches("#{ActiveRecord::Base.sanitize_sql_like(value)}%")
        when :null then value ? column.eq(nil) : column.not_eq(nil)
        else column.public_send(AREL_METHODS.fetch(op, op), value)
        end
      end
    end
  end
end
