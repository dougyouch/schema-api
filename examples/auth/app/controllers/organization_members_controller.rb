# frozen_string_literal: true

# /organizations/:organization_id/members: the same affiliations as users[].affiliations,
# seen from the organization. Managers must be members of the same organization.
class OrganizationMembersController < ApplicationController
  before_action :authenticate!
  before_action :require_application!, except: %i[index show]

  schema(model: 'AuthDB::Affiliation', root: :member, collection_root: :members) do
    model_attribute :id

    belongs_to :user, input: true, scope: :user_scope, render_key: true do
      model_attributes :name, :email
    end

    has_one :affiliation_attributes, input: true, model: :affiliation_attribute do
      model_attributes :department, :title, input: true
      belongs_to :manager_user, input: true, scope: :manager_scope, render_key: true do
        model_attribute :name
      end
    end

    timestamps
  end

  search do
    filter :user_id
    filter :'affiliation_attributes.department'
    filter :'affiliation_attributes.manager_user_id'
    sort :created_at, default: 'created_at'
  end

  parent :organization, scope: :organizations
  upsert_key :user_id
  bulk max: 100

  private

  def organizations
    return AuthDB::Organization.active if current_application

    AuthDB::Organization.active.where(id: current_user.affiliations.select(:organization_id))
  end

  def user_scope
    AuthDB::User.active
  end

  def manager_scope
    AuthDB::User.active.where(id: organization.affiliations.select(:user_id))
  end
end
