# frozen_string_literal: true

update_model do
  has_secure_password

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, uniqueness: true

  scope :active, -> { where(deleted_at: nil) }
end
