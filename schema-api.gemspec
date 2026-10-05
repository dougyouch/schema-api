# frozen_string_literal: true

require_relative 'lib/schema_api/version'

Gem::Specification.new do |s|
  s.name        = 'schema-api'
  s.version     = SchemaApi::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Rails controllers whose API is an inline, typed schema'
  s.description = 'Declare a resource API as a schema-model schema at the top of a Rails controller. The schema is ' \
                  'the allowlist for input, parses and type-checks requests, validates them, and is the only thing ' \
                  'rendered. Standard create, update, patch, upsert, bulk and search actions, nested resources, ' \
                  'optimistic locking and one error format come with it.'
  s.authors     = ['Doug Youch']
  s.email       = 'dougyouch@gmail.com'
  s.homepage    = 'https://github.com/dougyouch/schema-api'
  s.files       = Dir['lib/**/*.rb', 'README.md', 'LICENSE', 'DESIGN.md']
  s.required_ruby_version = '>= 3.3'

  s.add_dependency 'actionpack', '>= 7.1'
  s.add_dependency 'activerecord', '>= 7.1'
  s.add_dependency 'model-mapper', '>= 0.3'
  s.add_dependency 'schema-model', '>= 0.11'
  s.metadata['rubygems_mfa_required'] = 'true'
  s.metadata['source_code_uri'] = 'https://github.com/dougyouch/schema-api'
end
