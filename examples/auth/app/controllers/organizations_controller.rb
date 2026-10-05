# frozen_string_literal: true

# Tenants. Only applications create, change or delete them; users read the ones they belong to.
class OrganizationsController < ApplicationController
  include SchemaApi

  before_action :authenticate!
  before_action :require_application!, except: %i[index show]

  schema(model: 'AuthDB::Organization') do
    model_attribute :id
    model_attribute :name, input: true
    model_attribute :slug, input: :create
    attribute :member_count, :integer, value: ->(organization) { organization.affiliations.size }

    belongs_to :application do
      model_attribute :id
      model_attribute :name
    end

    model_attribute :created_at
    model_attribute :updated_at, lock: true

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

  before_assign :record_creator

  private

  def resource_scope
    organizations = AuthDB::Organization.active
    return organizations if current_application

    organizations.where(id: current_user.affiliations.select(:organization_id))
  end

  def scoped_resources
    super.includes(:affiliations)
  end

  def destroy_resource!(organization)
    organization.soft_delete!
  end

  def record_creator(context)
    context.record.application = current_application if context.creating?
  end
end
