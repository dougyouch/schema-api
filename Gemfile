# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# unreleased schema-model changes this gem relies on (:decimal, association _was_set?, parsing error codes);
# back to the released gem once they ship
gem 'schema-model', git: 'https://github.com/dougyouch/schema.git', branch: 'feat/schema-api-support'

group :development do
  gem 'rubocop'
end

group :spec do
  gem 'rack-test'
  gem 'rspec'
  gem 'simplecov'
  gem 'sqlite3'
end
