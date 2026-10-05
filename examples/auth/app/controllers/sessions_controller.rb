# frozen_string_literal: true

# POST /sessions logs in with email and password and returns a token good for an hour.
# GET /sessions lists the caller's active sessions; /sessions/current is the one in use;
# DELETE revokes.
class SessionsController < ApplicationController
  before_action :authenticate_user!, except: :create

  schema(model: 'AuthDB::Session', actions: %i[index show create destroy]) do
    model_attribute :id
    attribute :email, :string, write_only: true, model: false
    attribute :password, :string, write_only: true, model: false
    attribute :token, :string, value: :token.to_proc # only in the response to create
    model_attribute :expires_at
    model_attribute :ip_address
    model_attribute :user_agent
    model_attribute :created_at

    belongs_to :user do
      model_attribute :id
      model_attribute :name
      model_attribute :email
    end

    validates :email, :password, presence: true, on: :create
  end

  paginate :offset, limit: { default: 20, max: 50 }

  # runs inside the create transaction, after the input passed validation
  before_save :start_session, only: :create

  private

  def resource_scope
    return AuthDB::Session.all if action_name == 'create'

    current_user.sessions.active
  end

  def find_resource
    params[:id] == 'current' ? current_session : super
  end

  def destroy_resource!(session)
    session.revoke!
  end

  def start_session(context)
    user = AuthDB::User.active.find_by(email: context.input.email)
    raise Unauthorized, 'Email or password is incorrect' unless user&.authenticate(context.input.password)

    session = context.record
    session.assign_attributes(user: user, ip_address: request.remote_ip, user_agent: request.user_agent)
    session.issue_token!
  end
end
