# frozen_string_literal: true

module SchemaApi
  module Search
    # Parses search parameters with a schema built from the filters, so bad values and
    # unknown parameters are reported like any other bad input.
    class ParamsParser
      # Builds the schema class for a set of filters and a pagination config. Each filter
      # operator becomes an attribute named f<index>_<op>.
      # @param filters [Hash{String => Filter}]
      # @param pagination [Pagination::Config]
      # @return [Class]
      def self.build_schema_class(filters, pagination)
        Class.new do
          include ::Schema::All

          filters.values.each_with_index do |filter, index|
            filter.ops.each do |op|
              type, options = filter.param_type(op)
              attribute(:"f#{index}_#{op}", type, options)
            end
          end
          pagination.param_types.each { |name, type| attribute(name, type) }
        end
      end

      # @param definition [Definition]
      # @param pagination [Pagination::Config]
      # @param sort [Sort]
      # @param schema_class [Class] from {.build_schema_class}
      def initialize(definition, pagination, sort, schema_class)
        @filters = definition.filters
        @pagination = pagination
        @sort = sort
        @schema_class = schema_class
        @errors = ErrorList.new
        @labels = {}
      end

      # @param params [Hash]
      # @return [Query]
      # @raise [InvalidData]
      def parse(params)
        schema = @schema_class.from_hash(flatten(params.to_h.stringify_keys))
        add_parsing_errors(schema)
        order = parse_order(schema)
        query = build_query(schema, order)
        check_pagination(query)
        raise InvalidData.new('Search has invalid parameters', details: @errors.to_a) unless @errors.empty?

        query
      end

      private

      def flatten(params)
        params.each_with_object({}) do |(key, value), flat|
          if @pagination.param_names.include?(key)
            flat[key] = value
          elsif (filter = @filters[key])
            flatten_filter(filter, key, value, flat)
          else
            @errors.add(key, 'unknown_attribute', "#{key} is not a supported search parameter")
          end
        end
      end

      def flatten_filter(filter, key, value, flat)
        if value.is_a?(Hash)
          return value.each do |op, op_value|
            add_filter_value(filter, op.to_s.to_sym, "#{key}[#{op}]", op_value, flat)
          end
        end

        op = filter.default_op
        return @errors.add(key, 'operator_required', "#{key} needs an operator: #{filter.ops.join(', ')}") unless op

        add_filter_value(filter, op, key, value, flat)
      end

      def add_filter_value(filter, op, label, value, flat)
        unless filter.ops.include?(op)
          return @errors.add(label, 'unknown_attribute',
                             "#{label} is not a supported search parameter")
        end

        name = attribute_name(filter, op)
        @labels[name] = label
        flat[name] = value
      end

      def attribute_name(filter, op)
        "f#{@filters.values.index(filter)}_#{op}"
      end

      def add_parsing_errors(schema)
        schema.parsing_errors.each do |error|
          label = @labels.fetch(error.attribute.to_s, error.attribute.to_s)
          @errors.add(label, error.type, "#{label} #{error.message}")
        end
      end

      def parse_order(schema)
        order, errors = @sort.parse(schema.respond_to?(:sort) ? schema.sort : nil)
        @errors.concat(errors)
        order
      end

      def build_query(schema, order)
        Query.new(conditions: conditions(schema), order: order, limit: param(schema, :limit),
                  cursor_values: cursor_values(schema, order), page: param(schema, :page), count: param(schema, :count))
      end

      def conditions(schema)
        @filters.values.flat_map do |filter|
          filter.ops.filter_map do |op|
            name = attribute_name(filter, op)
            [filter, op, schema.public_send(name)] if schema.public_send(:"#{name}_was_set?") && !schema.public_send(name).nil?
          end
        end
      end

      def cursor_values(schema, order)
        token = param(schema, :cursor)
        return unless token

        Pagination::Cursor.decode(token, order)
      rescue ArgumentError
        @errors.add('cursor', 'invalid', 'Cursor is invalid or was made for a different sort')
        nil
      end

      def check_pagination(query)
        if query.limit && (query.limit < 1 || query.limit > @pagination.max_limit)
          @errors.add('limit', 'out_of_range', "Limit must be between 1 and #{@pagination.max_limit}")
        end
        @errors.add('page', 'out_of_range', 'Page must be 1 or more') if query.page && query.page < 1
      end

      def param(schema, name)
        schema.respond_to?(name) ? schema.public_send(name) : nil
      end
    end
  end
end
