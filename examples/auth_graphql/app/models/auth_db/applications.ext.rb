# frozen_string_literal: true

update_model do
  scope :active, -> { where(revoked_at: nil) }

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  # @return [Array(AuthDB::Application, String)] the application and its token, shown only now
  def self.issue!(name)
    token = "app_#{SecureRandom.urlsafe_base64(32)}"
    [create!(name: name, token_digest: digest(token)), token]
  end

  # @return [AuthDB::Application, nil]
  def self.authenticate(token)
    active.find_by(token_digest: digest(token)) if token.present?
  end
end
