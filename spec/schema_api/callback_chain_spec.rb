# frozen_string_literal: true

RSpec.describe SchemaApi::CallbackChain do
  let(:controller) do
    Class.new do
      attr_reader :log

      def initialize
        @log = []
      end

      def note
        @log << :note
      end

      def admin?(_context)
        false
      end

      def wrap(context)
        @log << [:wrap_start, context.action]
        yield
        @log << :wrap_end
      end
    end.new
  end
  let(:context) { Struct.new(:action).new(:update) }

  it 'runs befores, arounds and afters that apply, in order' do
    chain = described_class.new
    chain.add(:before, :save, [:note], {}, nil)
    chain.add(:before, :save, [], { except: :update }, -> { log << :skipped })
    chain.add(:before, :save, [], { unless: :admin? }, ->(ctx) { log << [:not_admin, ctx.action] })
    chain.add(:around, :save, [:wrap], {}, nil)
    chain.add(:around, :save, [], { if: -> { true } }, lambda { |_ctx, inner|
      log << :proc_start
      inner.call.tap { log << :proc_end }
    })
    chain.add(:after, :save, [], { only: %i[update] }, ->(_ctx) { log << :after })

    result = chain.run(controller, :save, context) do
      controller.log << :body
      42
    end

    expect(result).to eq(42)
    expect(controller.log).to eq([:note, %i[not_admin update], %i[wrap_start update], :proc_start, :body, :proc_end, :wrap_end, :after])
  end

  it 'copies independently' do
    chain = described_class.new
    copy = chain.dup
    copy.add(:before, :save, [:note], {}, nil)

    chain.run(controller, :save, context) { nil }
    expect(controller.log).to be_empty
  end
end
