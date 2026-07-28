require "rails_helper"

RSpec.describe Task, type: :model do
  describe "associacoes" do
    it { is_expected.to belong_to(:list) }
  end

  describe "validacoes" do
    it "e valida com os atributos da factory" do
      expect(build(:task)).to be_valid
    end

    it { is_expected.to validate_presence_of(:title) }

    it "exige uma lista" do
      expect(build(:task, list: nil)).not_to be_valid
    end

    it "aceita description e due_date nulos" do
      expect(build(:task, description: nil, due_date: nil)).to be_valid
    end

    it "aceita description e due_date preenchidos" do
      task = create(:task, description: "Comprar leite integral", due_date: Date.new(2026, 8, 1))
      expect(task.reload.description).to eq("Comprar leite integral")
      expect(task.reload.due_date).to eq(Date.new(2026, 8, 1))
    end

    # V-07: description e `text` sem limite algum no banco.
    it "recusa titulo acima de 200 caracteres" do
      expect(build(:task, title: "a" * 201)).not_to be_valid
    end

    it "aceita titulo de exatamente 200 caracteres" do
      expect(build(:task, title: "a" * 200)).to be_valid
    end

    it "recusa descricao acima de 10.000 caracteres" do
      expect(build(:task, description: "a" * 10_001)).not_to be_valid
    end

    it "aceita descricao de exatamente 10.000 caracteres" do
      expect(build(:task, description: "a" * 10_000)).to be_valid
    end
  end

  describe "completed" do
    it "nasce como false" do
      expect(described_class.new.completed).to be(false)
    end

    it "persiste o default sem que o payload informe o campo" do
      expect(create(:task).reload.completed).to be(false)
    end
  end

  describe "posse" do
    it "nao tem user_id proprio: a posse vem sempre da lista" do
      expect(described_class.column_names).not_to include("user_id")
    end

    it "chega ao dono atraves de list.user" do
      user = create(:user)
      task = create(:task, list: create(:list, user: user))
      expect(task.list.user).to eq(user)
    end
  end
end
