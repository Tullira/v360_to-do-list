FactoryBot.define do
  factory :task do
    list
    sequence(:title) { |n| "Tarefa #{n}" }
    description { nil }
    due_date { nil }
  end
end
