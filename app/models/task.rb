class Task < ApplicationRecord
  belongs_to :list

  validates :title, presence: true

  # A posse vem sempre da lista - Task nao tem user_id proprio.
  delegate :user, to: :list
end
