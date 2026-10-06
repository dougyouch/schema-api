# frozen_string_literal: true

module SchemaApi
  module Search
    # The filters and sorts a controller's index accepts. Only declared fields can be
    # filtered or sorted on.
    #
    # @example
    #   search do
    #     filter :make                              # ?make=Ford
    #     filter :model, op: :contains              # ?model=bron
    #     filter :year, op: %i[gte lte]             # ?year[gte]=2010
    #     filter :status, op: :in                   # ?status=active,sold
    #     filter :'owners.person_id'                # ?owners.person_id=5
    #     filter(:q, :string) { |scope, q| scope.where('make LIKE ?', "%#{q}%") }
    #     sort :year, :created_at, default: '-created_at'
    #   end
    class Definition
      # @return [Hash{String => Filter}]
      attr_reader :filters
      # @return [Array<String>] sortable schema fields
      attr_reader :sort_fields
      # @return [String, nil] e.g. "-created_at"
      attr_reader :default_sort

      def initialize
        @filters = {}
        @sort_fields = []
        @default_sort = nil
      end

      # @api private
      def initialize_copy(source)
        super
        @filters = source.filters.dup
        @sort_fields = source.sort_fields.dup
      end

      # Declares a filter.
      # @param name [Symbol] a schema field, a nested one ("owners.person_id"), or any name with a block
      # @param type [Symbol, nil] value type; taken from the schema field when nil
      # @param op [Symbol, Array<Symbol>] operators: eq, not_eq, in, contains, starts_with, gt, gte, lt, lte, null
      # @yield [scope, value] custom filtering, run in the controller; returns the scope
      # @return [void]
      def filter(name, type = nil, op: :eq, &block)
        @filters[name.to_s] = Filter.new(name, type, Array(op), block)
      end

      # Declares sortable fields.
      # @param names [Array<Symbol>] schema fields
      # @param default [String, nil] sort when none is given, e.g. "-created_at"
      # @return [void]
      def sort(*names, default: nil)
        @sort_fields |= names.map(&:to_s)
        @default_sort = default.to_s if default
      end

      # @api private
      def finalize!(schema_class, model)
        @model = model
        @sort = Sort.new(model, sort_columns(schema_class), default_sort)
        filters.each_value { |filter| filter.finalize!(schema_class, model) }
        @params_schemas = {}
      end

      # @param params [Hash] query parameters or a search body
      # @param pagination [Pagination::Config]
      # @return [Query]
      # @raise [InvalidData]
      def parse(params, pagination)
        ParamsParser.new(self, pagination, @sort, params_schema(pagination)).parse(params)
      end

      private

      def params_schema(pagination)
        @params_schemas[pagination] ||= ParamsParser.build_schema_class(filters, pagination)
      end

      def sort_columns(schema_class)
        sort_fields.to_h do |name|
          field = schema_class.api_field(name)
          unless field&.output_mapped? && field.model_name
            raise UnknownAttributeError,
                  "search sort #{name}: not a rendered model attribute of the schema"
          end

          [name, field.model_name.to_s]
        end
      end
    end
  end
end
