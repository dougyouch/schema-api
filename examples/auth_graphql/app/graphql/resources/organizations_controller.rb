# frozen_string_literal: true

module Resources
  # Tenants: the Organization type and the organizations and organization fields. Users see
  # the ones they belong to.
  class OrganizationsController < ApplicationController
    before_action :authenticate!

    schema(model: 'AuthDB::Organization') do
      model_attribute :id
      model_attribute :name, input: true
      model_attribute :slug, input: :create
      attribute :member_count, :integer, value: ->(organization) { organization.affiliations.size }, includes: :affiliations

      belongs_to :application do
        model_attributes :id, :name
      end

      timestamps
    end

    search do
      filter :name, op: :contains
      filter :slug, op: %i[eq in]
      sort :name, :created_at, default: 'name'
    end

    paginate %i[cursor offset], count: :optional
    soft_delete

    private

    def resource_scope
      return AuthDB::Organization.all if current_application

      AuthDB::Organization.where(id: current_user.affiliations.select(:organization_id))
    end
  end
end
