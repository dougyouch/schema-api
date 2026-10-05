# frozen_string_literal: true

# Tenants. Only applications create, change or delete them; users read the ones they belong to.
class OrganizationsController < ApplicationController
  before_action :authenticate!
  before_action :require_application!, except: %i[index show]

  schema(model: 'AuthDB::Organization') do
    model_attribute :id
    model_attribute :name, input: true
    model_attribute :slug, input: :create
    attribute :member_count, :integer, value: ->(organization) { organization.affiliations.size }, includes: :affiliations

    # the application that created it, recorded by the server
    belongs_to :application, set: :current_application_id, on: :create do
      model_attributes :id, :name
    end

    timestamps

    validates :name, presence: true
    validates :slug, presence: true,
                     format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: 'must be lowercase words joined by dashes' }
  end

  search do
    filter :name, op: :contains
    filter :slug, op: %i[eq in]
    sort :name, :created_at, default: 'name'
  end

  paginate %i[cursor offset], count: :optional
  upsert_key :slug
  bulk max: 50
  soft_delete

  private

  def resource_scope
    return AuthDB::Organization.all if current_application

    AuthDB::Organization.where(id: current_user.affiliations.select(:organization_id))
  end
end
