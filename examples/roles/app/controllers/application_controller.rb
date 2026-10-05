# frozen_string_literal: true

# This service sits behind a gateway that has already checked the caller's auth session and
# passes the acting user's id in X-User-Id. Reads are open to callers inside the network;
# writes record who made them.
class ApplicationController < ActionController::API
  # actions come from each controller's schema; errors anywhere render in SchemaApi's format
  include SchemaApi

  private

  # @return [Integer, nil]
  def acting_user_id
    Integer(request.headers['X-User-Id'], exception: false)
  end

  def require_acting_user!
    raise SchemaApi::Forbidden, 'X-User-Id is required to make changes' unless acting_user_id
  end
end
