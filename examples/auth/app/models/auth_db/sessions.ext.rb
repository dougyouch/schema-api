# frozen_string_literal: true

update_model do
  validates :user, presence: true

  # the plain token, only on the instance that issued it
  attr_reader :token

  scope :active, -> { where(revoked_at: nil).where(expires_at: Time.current..) }

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  # @return [AuthDB::Session, nil] the active session for a bearer token, if its user is active
  def self.authenticate(token)
    return if token.blank?

    active.joins(:user).merge(AuthDB::User.active).find_by(token_digest: digest(token))
  end

  def issue_token!(ttl = 1.hour)
    @token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(@token)
    self.expires_at = ttl.from_now
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
