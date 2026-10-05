# frozen_string_literal: true

ActiveRecord::Schema[8.1].define(version: 2026_10_05_000000) do
  create_table :roles do |t|
    t.string :name, null: false
    t.string :description
    t.timestamps
  end
  add_index :roles, :name, unique: true

  # what can be done: resource "cars", action "write"
  create_table :permissions do |t|
    t.string :name, null: false
    t.string :description
    t.string :resource, null: false
    t.string :action, null: false
    t.timestamps
  end
  add_index :permissions, %i[resource action], unique: true

  create_table :role_permissions do |t|
    t.references :role, null: false, foreign_key: true
    t.references :permission, null: false, foreign_key: true
    t.timestamps
  end
  add_index :role_permissions, %i[role_id permission_id], unique: true

  # a user's role in one organization; user and organization ids come from the auth service
  create_table :user_roles do |t|
    t.integer :organization_id, null: false
    t.integer :user_id, null: false
    t.references :role, null: false, foreign_key: true
    t.integer :creator_id, null: false
    t.integer :updated_by_user_id, null: false
    t.timestamps
  end
  add_index :user_roles, %i[organization_id user_id role_id], unique: true
  add_index :user_roles, %i[user_id organization_id]
end
