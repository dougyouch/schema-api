# frozen_string_literal: true

# Two kinds of callers: users with a session token (Authorization: Bearer <token>) and
# other services with an application token (X-Application-Token: app_...). The resources
# inherit these, so their before_actions decide what each GraphQL field may return.
class ApplicationController < ActionController::API
  include SchemaApi

  private

  def current_application
    return @current_application if defined?(@current_application)

    @current_application = AuthDB::Application.authenticate(request.headers['X-Application-Token'])
  end

  def current_session
    return @current_session if defined?(@current_session)

    @current_session = AuthDB::Session.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1])
  end

  def current_user
    current_session&.user
  end

  def authenticate!
    raise Unauthorized, 'A session or application token is required' unless current_user || current_application
  end

  def authenticate_user!
    raise Unauthorized, 'A session token is required' unless current_user
  end
end
