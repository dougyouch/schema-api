# frozen_string_literal: true

RSpec.describe SchemaApi::Pagination::Cursor do
  let(:order) { SchemaApi::Search::Sort::Order.new([['created_at', :desc], ['born_on', :asc], ['price', :asc], ['id', :asc]]) }
  let(:record) do
    Struct.new(:created_at, :born_on, :price, :id).new(Time.utc(2026, 1, 2, 3, 4, 5.123456r), Date.new(2000, 1, 31), BigDecimal('9.99'), 7)
  end

  it 'round-trips times, dates, decimals and plain values' do
    token = described_class.encode(order, record)

    expect(described_class.decode(token, order)).to eq([record.created_at, record.born_on, record.price, 7])
  end

  it 'rejects tokens for another sort, and malformed tokens' do
    token = described_class.encode(order, record)
    other = SchemaApi::Search::Sort::Order.new([['id', :asc]])

    expect { described_class.decode(token, other) }.to raise_error(ArgumentError)
    expect { described_class.decode('!!!', order) }.to raise_error(ArgumentError)
    bad_value = Base64.urlsafe_encode64(JSON.generate('s' => 'id', 'v' => [{ 'x' => 1 }]))
    expect { described_class.decode(bad_value, other) }.to raise_error(ArgumentError, 'malformed cursor value')
  end
end
