class User < ApplicationRecord
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  # As mais usadas em vazamentos publicos, ja normalizadas em minusculas. Nao
  # substitui uma checagem contra base de vazamentos, mas corta o alvo mais
  # facil - que e justamente o que a forca bruta tenta primeiro.
  COMMON_PASSWORDS = %w[
    12345678 123456789 1234567890 password senha123 qwertyui abc12345
    iloveyou princess sunshine password1 football baseball welcome1
  ].freeze

  # has_secure_password ja traz, de graca:
  #   - presenca da senha no cadastro;
  #   - confirmacao (password_confirmation), quando o campo e informado;
  #   - maximo de 72 bytes, que e onde o bcrypt trunca em silencio.
  # Por isso nada disso e repetido abaixo: duplicar renderia duas mensagens de
  # erro para a mesma falha.
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
  validate :password_not_common

  private

  def normalize_email
    self.email = email.to_s.downcase.strip if email.present?
  end

  def password_not_common
    return if password.blank?
    return unless COMMON_PASSWORDS.include?(password.downcase)

    errors.add(:password, "e facil demais de adivinhar. Escolha outra.")
  end
end
