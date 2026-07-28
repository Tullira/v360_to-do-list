class List < ApplicationRecord
  belongs_to :user

  has_many :tasks, dependent: :destroy

  # O limite de tamanho e o que impede um POST de varios MB de ser aceito e
  # persistido - nao ha nada no banco segurando isso (`string` sem limit).
  validates :name, presence: true, length: { maximum: 120 }
end
