# frozen_string_literal: true

# GET /authorize's query parameters, parsed and validated by a plain schema-model schema.
class AuthorizationQuery
  include Schema::All

  attribute :organization_id, :integer
  attribute :user_id, :integer
  attribute :resource, :string
  attribute :action, :string

  validates :organization_id, :user_id, :resource, :action, presence: true
end
