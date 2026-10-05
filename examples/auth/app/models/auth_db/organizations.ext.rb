# frozen_string_literal: true

update_model do
  scope :active, -> { where(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
