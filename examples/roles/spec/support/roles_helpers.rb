# frozen_string_literal: true

module RolesHelpers
  ADMIN_ID = 1

  def headers(user_id: ADMIN_ID)
    { 'X-User-Id' => user_id.to_s, 'Content-Type' => 'application/json' }
  end

  def body(payload)
    payload.to_json
  end

  def json
    response.parsed_body
  end

  def permission(resource, action)
    RolesDB::Permission.create!(resource: resource, action: action, name: "#{action} #{resource}")
  end

  def role(name, *permissions)
    RolesDB::Role.create!(name: name).tap { |role| permissions.each { |p| role.role_permissions.create!(permission: p) } }
  end

  def grant(role, organization_id:, user_id:)
    RolesDB::UserRole.create!(role: role, organization_id: organization_id, user_id: user_id, creator_id: ADMIN_ID,
                              updated_by_user_id: ADMIN_ID)
  end
end
