# frozen_string_literal: true

# Two kinds of callers: users with a session token (Authorization: Bearer <token>) and
# other services with an application token (X-Application-Token: app_...).
class ApplicationController < ActionController::API
  # actions come from each controller's schema; errors anywhere render in SchemaApi's format
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

  def current_application_id
    current_application&.id
  end

  def authenticate!
    raise Unauthorized, 'A session or application token is required' unless current_user || current_application
  end

  def authenticate_user!
    raise Unauthorized, 'A session token is required' unless current_user
  end

  def require_application!
    raise SchemaApi::Forbidden, 'Only applications can do this' unless current_application
  end
end
