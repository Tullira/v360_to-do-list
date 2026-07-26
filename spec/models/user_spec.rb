require "rails_helper"

RSpec.describe User, type: :model do
  describe "associacoes" do
    it { is_expected.to have_many(:lists).dependent(:destroy) }
  end

  describe "validacoes" do
    subject { create(:user) }

    it "e valido com os atributos da factory" do
      expect(build(:user)).to be_valid
    end

    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:email) }

    it { is_expected.to validate_uniqueness_of(:username).case_insensitive }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }

    it { is_expected.to allow_value("ana@example.com").for(:email) }
    it { is_expected.not_to allow_value("sem-arroba").for(:email) }
    it { is_expected.not_to allow_value("ana@").for(:email) }
  end

  describe "senha" do
    it { is_expected.to have_secure_password }

    it "exige no minimo 8 caracteres" do
      user = build(:user, password: "curta12")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "aceita uma senha com 8 caracteres ou mais" do
      expect(build(:user, password: "12345678")).to be_valid
    end

    it "nao armazena a senha em texto puro" do
      user = create(:user, password: "senha_super_secreta")
      expect(user.password_digest).to be_present
      expect(user.password_digest).not_to eq("senha_super_secreta")
    end

    it "autentica com a senha correta" do
      user = create(:user, password: "senha_super_secreta")
      expect(user.authenticate("senha_super_secreta")).to eq(user)
    end

    it "nao autentica com a senha errada" do
      user = create(:user, password: "senha_super_secreta")
      expect(user.authenticate("senha_errada")).to be(false)
    end
  end

  describe "normalizacao de email" do
    it "guarda o email em minusculas" do
      user = create(:user, email: "Ana@Example.COM")
      expect(user.email).to eq("ana@example.com")
    end

    it "rejeita email ja cadastrado com caixa diferente" do
      create(:user, email: "ana@example.com")
      expect(build(:user, email: "ANA@EXAMPLE.COM")).not_to be_valid
    end
  end

  describe "role" do
    it "nasce como 'user'" do
      expect(described_class.new.role).to eq("user")
    end

    it "persiste o default sem que o cadastro informe o campo" do
      expect(create(:user).reload.role).to eq("user")
    end
  end
end
