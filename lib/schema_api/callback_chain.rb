# frozen_string_literal: true

module SchemaApi
  # The callbacks a controller registered around the write steps (:validation, :assign,
  # :save, :commit), plus validate_input methods. Each callback is a method name or a block,
  # with only:/except: (action names) and if:/unless: conditions. Methods and blocks are
  # given the {WriteContext}; methods and lambdas that take no arguments are called without it.
  class CallbackChain
    # One registered callback.
    #
    # @!attribute kind
    #   @return [Symbol] :before, :after, :around or :validate
    # @!attribute step
    #   @return [Symbol]
    # @!attribute callable
    #   @return [Symbol, Proc]
    # @!attribute options
    #   @return [Hash] only:, except:, if:, unless:
    Callback = Struct.new(:kind, :step, :callable, :options)

    def initialize
      @callbacks = []
    end

    # @api private
    def initialize_copy(source)
      super
      @callbacks = source.callbacks.dup
    end

    # @param kind [Symbol]
    # @param step [Symbol]
    # @param names [Array<Symbol>]
    # @param options [Hash]
    # @param block [Proc, nil]
    # @return [self]
    def add(kind, step, names, options, block)
      (names + [block].compact).each { |callable| @callbacks << Callback.new(kind, step, callable, options) }
      self
    end

    # Runs a step's before callbacks, its around callbacks wrapped around the block, then its after callbacks.
    # @param controller [ActionController::Metal]
    # @param step [Symbol]
    # @param context [WriteContext]
    # @return [Object] the block's result
    def run(controller, step, context, &block)
      applicable = applicable(controller, step, context)
      applicable.select { |cb| cb.kind == :before }.each { |cb| invoke(controller, cb.callable, context) }
      result = nil
      core = -> { result = block.call }
      wrap_arounds(controller, applicable.select { |cb| cb.kind == :around }, context, core).call
      applicable.select { |cb| cb.kind == :after }.each { |cb| invoke(controller, cb.callable, context) }
      result
    end

    # Calls the validate_input methods that apply.
    # @return [void]
    def validate(controller, context)
      applicable(controller, :validation, context).select { |cb| cb.kind == :validate }.each do |cb|
        invoke(controller, cb.callable, context)
      end
    end

    protected

    # @return [Array<Callback>]
    attr_reader :callbacks

    private

    def applicable(controller, step, context)
      @callbacks.select { |cb| cb.step == step && applies?(controller, cb.options, context) }
    end

    def applies?(controller, options, context)
      action = context.action.to_s
      return false if options[:only] && Array(options[:only]).map(&:to_s).exclude?(action)
      return false if options[:except] && Array(options[:except]).map(&:to_s).include?(action)
      return false if options[:if] && !invoke(controller, options[:if], context)

      !(options[:unless] && invoke(controller, options[:unless], context))
    end

    def wrap_arounds(controller, arounds, context, block)
      arounds.reverse.reduce(block) do |inner, cb|
        -> { invoke_around(controller, cb.callable, context, inner) }
      end
    end

    def invoke_around(controller, callable, context, inner)
      return controller.instance_exec(context, inner, &callable) if callable.is_a?(Proc)

      controller.send(callable, context) { inner.call }
    end

    def invoke(controller, callable, context)
      if callable.is_a?(Proc)
        return callable.arity.zero? ? controller.instance_exec(&callable) : controller.instance_exec(context, &callable)
      end

      method = controller.method(callable)
      method.arity.zero? ? method.call : method.call(context)
    end
  end
end
