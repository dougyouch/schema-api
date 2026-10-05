# frozen_string_literal: true

update_model do
  validates :user, :organization, presence: true
end
