# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :tenants do |t|
    t.string :name
  end

  create_table :manufacturers do |t|
    t.integer :tenant_id
    t.string :name
    t.string :code
  end

  create_table :cars do |t|
    t.integer :tenant_id, null: false
    t.string :vin, null: false
    t.string :make
    t.string :model
    t.integer :year
    t.decimal :price, precision: 10, scale: 2
    t.integer :status, default: 0
    t.integer :manufacturer_id
    t.json :options
    t.string :pin
    t.integer :created_by_id
    t.integer :updated_by_id
    t.datetime :deleted_at
    t.timestamps
  end
  add_index :cars, %i[tenant_id vin], unique: true

  create_table :people do |t|
    t.string :name
  end

  create_table :owners do |t|
    t.integer :car_id
    t.integer :person_id
    t.date :since
  end

  create_table :users do |t|
    t.integer :tenant_id
    t.string :name
    t.string :email
    t.integer :version_number, default: 0
    t.timestamps
  end

  create_table :affiliations do |t|
    t.integer :user_id
    t.integer :tenant_id
    t.timestamps
  end
  add_index :affiliations, %i[user_id tenant_id], unique: true

  create_table :affiliation_attributes do |t|
    t.integer :affiliation_id
    t.string :department
    t.string :title
    t.timestamps
  end
  add_index :affiliation_attributes, :affiliation_id, unique: true

  create_table :affiliation_roles do |t|
    t.integer :affiliation_id
    t.string :name
  end
end
