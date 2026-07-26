FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "usuario#{n}" }
    sequence(:email) { |n| "usuario#{n}@example.com" }
    password { "senha_super_secreta" }
  end
end
