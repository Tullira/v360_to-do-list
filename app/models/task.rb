class Task < ApplicationRecord
  belongs_to :list

  # description e `text`, sem limite algum no banco: sem estas validacoes uma
  # unica requisicao enche o disco da droplet.
  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 10_000 }

  # A posse vem sempre da lista - Task nao tem user_id proprio.
  delegate :user, to: :list
end
