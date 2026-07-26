class User < ApplicationRecord
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  has_secure_password

  has_many :lists, dependent: :destroy

  before_validation :normalize_email

  validates :username, presence: true, uniqueness: { case_sensitive: false }
  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: EMAIL_FORMAT }
  # allow_nil para nao exigir a senha em updates que nao a alteram.
  # A presenca no cadastro ja vem do has_secure_password.
  validates :password, length: { minimum: 8 }, allow_nil: true

  private

  def normalize_email
    self.email = email.to_s.downcase.strip if email.present?
  end
end
