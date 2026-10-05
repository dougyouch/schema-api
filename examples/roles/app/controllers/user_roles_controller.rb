# frozen_string_literal: true

# A user's roles in an organization. Who granted a role and who last changed it come from
# X-User-Id, never from the body.
class UserRolesController < ApplicationController
  include SchemaApi

  before_action :require_acting_user!, except: %i[index show]

  schema(model: 'RolesDB::UserRole') do
    model_attribute :id
    model_attribute :organization_id, input: :create
    model_attribute :user_id, input: :create
    belongs_to :role, input: true, scope: :all, render_key: true do
      model_attribute :name
    end
    model_attribute :creator_id
    model_attribute :updated_by_user_id
    model_attribute :created_at
    model_attribute :updated_at, lock: true

    validates :organization_id, :user_id, presence: true
  end

  search do
    filter :organization_id
    filter :user_id
    filter :role_id, op: %i[eq in]
    sort :created_at, default: 'created_at'
  end

  paginate %i[cursor offset], limit: { default: 50, max: 200 }, count: :optional
  upsert_key :organization_id, :user_id, :role_id
  bulk max: 200

  validate_input :no_self_grants
  before_save :record_actor

  private

  def no_self_grants(context)
    return unless context.input.user_id == acting_user_id

    context.errors.add('user_id', :self_grant, "You can't change your own roles")
  end

  def record_actor(context)
    context.record.creator_id = acting_user_id if context.creating?
    context.record.updated_by_user_id = acting_user_id
  end
end
