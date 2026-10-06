# frozen_string_literal: true

RSpec.describe SchemaApi::Graphql::RequestParser do
  def parse(body)
    described_class.new(body.is_a?(String) ? body : JSON.generate(body)).parse
  end

  it 'reads the query, variables and operation name' do
    request = parse(query: '{ cars { nodes { id } } }', variables: { 'id' => 1 }, operationName: 'A')

    expect(request.to_h).to eq(query: '{ cars { nodes { id } } }', variables: { 'id' => 1 }, operation_name: 'A')
  end

  it 'treats missing or blank variables as none' do
    expect(parse(query: '{ a }').variables).to eq({})
    expect(parse(query: '{ a }', variables: ' ').variables).to eq({})
  end

  it 'raises malformed_request for anything else' do
    {
      'not json' => 'Request body is not valid JSON',
      '[]' => 'Request body must be a JSON object',
      { query: ' ' } => 'query is required',
      { query: '{ a }', variables: '[1]' } => 'variables must be a JSON object',
      { query: '{ a }', variables: 'nope' } => 'variables is not valid JSON',
      { query: '{ a }', variables: [1] } => 'variables must be an object',
      { query: '{ a }', operationName: 1 } => 'operationName must be a string'
    }.each do |body, message|
      expect { parse(body) }.to raise_error(SchemaApi::MalformedRequest, message)
    end
  end
end
