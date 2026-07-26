require "rails_helper"

RSpec.describe List, type: :model do
  describe "associacoes" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:tasks).dependent(:destroy) }
  end

  describe "validacoes" do
    it "e valida com os atributos da factory" do
      expect(build(:list)).to be_valid
    end

    it { is_expected.to validate_presence_of(:name) }

    it "exige um dono" do
      expect(build(:list, user: nil)).not_to be_valid
    end
  end

  describe "posse" do
    it "pertence a um unico usuario" do
      user = create(:user)
      list = create(:list, user: user)
      expect(list.user).to eq(user)
    end

    it "leva as tarefas junto ao ser destruida" do
      list = create(:list)
      create_list(:task, 2, list: list)
      expect { list.destroy }.to change(Task, :count).by(-2)
    end
  end
end
