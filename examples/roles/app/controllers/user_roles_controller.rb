# frozen_string_literal: true

# A user's roles in an organization. Who granted a role and who last changed it come from
# X-User-Id (set:), never from the body.
class UserRolesController < ApplicationController
  before_action :require_acting_user!, except: %i[index show]

  schema(model: 'RolesDB::UserRole') do
    model_attribute :id
    model_attributes :organization_id, :user_id, input: :create
    belongs_to :role, input: true, scope: :all, render_key: true do
      model_attribute :name
    end
    # set by the server from X-User-Id; a client sending them is ignored
    model_attribute :creator_id, set: :acting_user_id, on: :create
    model_attribute :updated_by_user_id, set: :acting_user_id
    timestamps

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

  private

  def no_self_grants(context)
    return unless context.input.user_id == acting_user_id

    context.errors.add('user_id', :self_grant, "You can't change your own roles")
  end
end
