# frozen_string_literal: true

ActiveRecord::Schema[8.1].define(version: 2026_10_05_000000) do
  # server-to-server callers; the token is shown once, only its digest is stored
  create_table :applications do |t|
    t.string :name, null: false
    t.string :token_digest, null: false
    t.datetime :revoked_at
    t.timestamps
  end
  add_index :applications, :token_digest, unique: true

  create_table :users do |t|
    t.string :name, null: false
    t.string :email, null: false
    t.string :password_digest, null: false
    t.datetime :deleted_at
    t.timestamps
  end
  add_index :users, :email, unique: true

  # tenants
  create_table :organizations do |t|
    t.string :name, null: false
    t.string :slug, null: false
    t.references :application, foreign_key: true
    t.datetime :deleted_at
    t.timestamps
  end
  add_index :organizations, :slug, unique: true

  create_table :affiliations do |t|
    t.references :user, null: false, foreign_key: true
    t.references :organization, null: false, foreign_key: true
    t.timestamps
  end
  add_index :affiliations, %i[user_id organization_id], unique: true

  # organization-level details for an affiliation
  create_table :affiliation_attributes do |t|
    t.references :affiliation, null: false, foreign_key: true, index: { unique: true }
    t.string :department
    t.string :title
    t.references :manager_user, foreign_key: { to_table: :users }
    t.timestamps
  end

  # a login; the token is good for an hour
  create_table :sessions do |t|
    t.references :user, null: false, foreign_key: true
    t.string :token_digest, null: false
    t.datetime :expires_at, null: false
    t.datetime :revoked_at
    t.string :ip_address
    t.string :user_agent
    t.timestamps
  end
  add_index :sessions, :token_digest, unique: true
end
