# frozen_string_literal: true

update_model do
  validates :role, :permission, presence: true
end
