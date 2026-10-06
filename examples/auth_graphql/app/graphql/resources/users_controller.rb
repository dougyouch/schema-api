# frozen_string_literal: true

module Resources
  # Users and their organization affiliations: the User type and the users and user fields.
  # Applications see everyone; a user sees themselves and the people in their organizations.
  class UsersController < ApplicationController
    before_action :authenticate!

    # input: marks what mutations will accept; queries only read
    schema(model: 'AuthDB::User') do
      model_attribute :id
      model_attributes :name, :email, input: true
      attribute :password, :string, write_only: true # accepted by mutations, never a field

      has_many :affiliations, input: true, key: :organization_id do
        model_attribute :id
        belongs_to :organization, input: true, scope: :organization_scope, render_key: true do
          model_attributes :name, :slug
        end

        has_one :affiliation_attributes, input: true, model: :affiliation_attribute do
          model_attributes :department, :title, input: true
          belongs_to :manager_user, input: true, scope: :manager_scope do
            model_attributes :id, :name
          end
        end
        model_attribute :created_at
      end

      timestamps
    end

    search do
      filter :name, op: :contains
      filter :email
      filter :'affiliations.organization_id'
      sort :name, :created_at, default: 'name'
    end

    paginate %i[cursor offset], limit: { default: 25, max: 100 }, count: :optional
    soft_delete

    private

    def resource_scope
      return AuthDB::User.all if current_application

      shared = AuthDB::Affiliation.where(organization_id: current_user.affiliations.select(:organization_id))
      AuthDB::User.where(id: shared.select(:user_id)).or(AuthDB::User.where(id: current_user.id))
    end

    def organization_scope
      AuthDB::Organization.active
    end

    def manager_scope
      AuthDB::User.active
    end
  end
end
