# frozen_string_literal: true

class Tenant < ActiveRecord::Base
end

class Manufacturer < ActiveRecord::Base
end

class Person < ActiveRecord::Base
end

class Owner < ActiveRecord::Base
  belongs_to :car
  belongs_to :person, optional: true
  validates :person_id, presence: true
end

class Car < ActiveRecord::Base
  belongs_to :tenant
  belongs_to :manufacturer, optional: true
  has_many :owners, dependent: :destroy
  enum :status, { active: 0, sold: 1 }
  validates :vin, presence: true
  validates :year, numericality: { greater_than: 1885 }, allow_nil: true
end

module AuthDB
  class AffiliationRole < ActiveRecord::Base
    self.table_name = 'affiliation_roles'
  end

  class AffiliationAttribute < ActiveRecord::Base
    self.table_name = 'affiliation_attributes'
  end

  class Affiliation < ActiveRecord::Base
    self.table_name = 'affiliations'
    belongs_to :user, class_name: 'AuthDB::User'
    has_one :details, class_name: 'AuthDB::AffiliationAttribute', dependent: :destroy
    has_many :roles, class_name: 'AuthDB::AffiliationRole', dependent: :destroy
  end

  class User < ActiveRecord::Base
    self.table_name = 'users'
    has_many :affiliations, class_name: 'AuthDB::Affiliation', dependent: :destroy

    def bump_version_number!
      increment!(:version_number)
    end
  end
end
