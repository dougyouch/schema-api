# frozen_string_literal: true

update_model do
  has_secure_password

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, uniqueness: true

  scope :active, -> { where(deleted_at: nil) }

  # soft delete: the row stays for audit and foreign keys, its sessions end
  def soft_delete!
    transaction do
      update!(deleted_at: Time.current)
      sessions.active.update_all(revoked_at: Time.current)
    end
  end
end
