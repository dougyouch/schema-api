# frozen_string_literal: true

module Resources
  # The caller's active logins: the Session type and the sessions and session fields.
  # session(id: "current") is the one making the request.
  class SessionsController < ApplicationController
    before_action :authenticate_user!

    schema(model: 'AuthDB::Session') do
      model_attribute :id
      model_attributes :expires_at, :ip_address, :user_agent, :created_at

      belongs_to :user do
        model_attributes :id, :name, :email
      end
    end

    paginate :offset, limit: { default: 20, max: 50 }

    private

    def resource_scope
      current_user.sessions.active
    end

    def find_resource
      params[:id] == 'current' ? current_session : super
    end
  end
end
