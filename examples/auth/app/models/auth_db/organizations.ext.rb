# frozen_string_literal: true

update_model do
  scope :active, -> { where(deleted_at: nil) }
end
