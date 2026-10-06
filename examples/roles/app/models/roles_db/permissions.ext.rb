# frozen_string_literal: true

update_model do
  # @return [ActiveRecord::Relation] permissions a user has in an organization, through their roles
  def self.granted_to(organization_id:, user_id:)
    role_ids = RolesDB::UserRole.where(organization_id: organization_id, user_id: user_id).select(:role_id)
    where(id: RolesDB::RolePermission.where(role_id: role_ids).select(:permission_id))
  end
end
