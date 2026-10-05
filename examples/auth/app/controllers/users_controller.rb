# frozen_string_literal: true

# Users and their organization affiliations. Applications create and import users and
# manage affiliations; a user can read people in their organizations and update themselves.
class UsersController < ApplicationController
  include SchemaApi

  before_action :authenticate!
  before_action :require_application!, only: %i[create upsert bulk_create bulk_update bulk_upsert]
  before_action :require_self_or_application!, only: %i[update destroy]

  schema(model: 'AuthDB::User') do
    model_attribute :id
    model_attribute :name, input: true
    model_attribute :email, input: true
    # model: false: a PUT without a password must keep the current one, so a hook sets it
    attribute :password, :string, write_only: true, model: false

    has_many :affiliations, input: true, key: :organization_id do
      model_attribute :id
      belongs_to :organization, input: true, scope: :organization_scope, render_key: true do
        model_attribute :name
        model_attribute :slug
      end

      has_one :affiliation_attributes, input: true, model: :affiliation_attribute do
        model_attribute :department, input: true
        model_attribute :title, input: true
        belongs_to :manager_user, input: true, scope: :manager_scope do
          model_attribute :id
          model_attribute :name
        end
      end
      model_attribute :created_at
    end

    model_attribute :created_at
    model_attribute :updated_at, lock: true

    validates :name, presence: true
    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :password, presence: true, on: :create
    validates :password, length: { minimum: 8 }, allow_nil: true
  end

  search do
    filter :name, op: :contains
    filter :email
    filter :'affiliations.organization_id'
    sort :name, :created_at, default: 'name'
  end

  paginate %i[cursor offset], limit: { default: 25, max: 100 }, count: :optional
  upsert_key :email
  bulk max: 100

  # judged by what the write changed, so a user can PUT back their own GET response
  after_save :only_applications_change_affiliations
  before_assign :assign_password
  after_commit :end_other_sessions, only: :update, if: ->(context) { context.input.password }

  private

  # applications see everyone; a user sees themselves and the people in their organizations
  def resource_scope
    users = AuthDB::User.active
    return users if current_application

    shared = AuthDB::Affiliation.where(organization_id: current_user.affiliations.select(:organization_id))
    users.where(id: shared.select(:user_id)).or(users.where(id: current_user.id))
  end

  def organization_scope
    AuthDB::Organization.active
  end

  def manager_scope
    AuthDB::User.active
  end

  def destroy_resource!(user)
    user.soft_delete!
  end

  def require_self_or_application!
    return if current_application || resource == current_user

    raise SchemaApi::Forbidden, 'You can only change your own account'
  end

  # raising here rolls the write back
  def only_applications_change_affiliations(context)
    return if current_application
    return unless context.changes.paths.values.flatten.any? { |path| path.start_with?('affiliations') }

    raise SchemaApi::Forbidden.new('Only applications can change affiliations',
                                   details: [{ field: 'affiliations', error: 'forbidden',
                                               message: 'Only applications can change affiliations' }])
  end

  def assign_password(context)
    context.record.password = context.input.password if context.input.password
  end

  def end_other_sessions(context)
    context.record.sessions.active.where.not(id: current_session&.id).update_all(revoked_at: Time.current)
  end
end
