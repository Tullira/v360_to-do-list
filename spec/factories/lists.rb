FactoryBot.define do
  factory :list do
    user
    sequence(:name) { |n| "Lista #{n}" }
  end
end
